extends TileMap

const CHUNK_SIZE: int = 4000
const SEND_FREQUENCY: float = 0.01
const RE_REQUEST_INITIAL_MAP_DATA_TIMEOUT: float = 10.0

# Map transfer compression mode and maximum uncompressed data size.
# This size is a bit of a guess, hoping the compression
# works to keep it under the buffer size limit, which is a gamble
# Worst case from testing for each type is:
# COMPRESSION_FASTLZ  - 110696 compresses to 65006
# COMPRESSION_DEFLATE - 170000 compresses to 61283
# COMPRESSION_ZSTD    - 160000 compresses to 62934

# COMPRESSION_FASTLZ  - uses less CPU/is faster but compresses less It is meant for when speed and low CPU load is more important than bandwidth
# COMPRESSION_ZSTD is - supposed to be a lot faster than 1 at the expense of just a little compression
# COMPRESSION_DEFLATE - doesn't really offer any benefit unless maximum compression is paramount
# COMPRESSION_GZIP is - not better than any other option. It is just available for compatibility.
# COMPRESSION_BROTLI  - only supports decompression.

# So for a given compression type, I set these to:
# COMPRESSION_FASTLZ  - 110000
# COMPRESSION_DEFLATE - 170000
# COMPRESSION_ZSTD    - 150000
const MAP_TRANSFER_MAX_UNCOMPRESSED_DATA_SIZE: int = 150000
const MAP_TRANSFER_COMPRESSION_MODE: int = FileAccess.COMPRESSION_ZSTD

@export var tile_modification_particles_controller: Node2D

var map_generated: bool = false

#No longer using arrays, read/write requires an indexing system which negates the performance benefit of using array index overlap as link. Reading Positions and IDs separately may be faster if staggered separately but can be added later and merged into local dictionaries.

#Last change from server, considered highest authority on accuracy
var synced_data: Dictionary = {}
#Current map state, presumably faster than reading tilemap again
var current_data: Dictionary = {}
#Local modifications buffered until next sync cycle, current data includes these changes
var changed_data: Dictionary = {}

# current_data is the "best" reality for clients to work from and
# synced_data is the "best" data for the server to work from

#NOTE : Godot passes all dictionaries by reference, remember that.

var server_data_changed: bool = false

var current_cycle_time: float = 0.0
var re_request_initial_map_data_timer: float = 0.0

var local_player_initial_map_data_last_chunk_id_received: int = 0

#Changes the server has received and accepted, and is waiting to send back to all clients later
var server_buffered_changes: Dictionary = {}

var stored_player_inventory_drops: Dictionary = {}

var buffered_changes_received_from_server: Array[Dictionary] = []

var server_side_per_player_initial_map_data: Dictionary = {}

var map_download_finished: bool = false
var map_initialization_started: bool = false

var valid_resource_generation_tiles: Array = []

var max_radius_in_tiles: int = -1

var single_tile_width: int = 16

var generate_simple_world: bool = true


func _ready() -> void:
	# Without this, sending a StreamPeerBuffer over an RPC generates the error
	# "Cannot convert argument 1 from Object to Object" on the receiving end
	# and fails.
	# https://github.com/godotengine/godot/issues/82718
	multiplayer.allow_object_decoding = true
	#From Ben : Should check if this is safe to use

	if Globals.is_server:
		if not load_saved_map():
			generate_map()
		Globals.initial_map_load_finished = true
		map_download_finished = true
	else:
		visible = false
		request_initial_map_data.rpc_id(1)

	Globals.world_map = self


func get_depth_function(
	x: float, width_scale: float, height_scale: float, crater_scale: float
) -> float:
	# Desmos Formula:
	#y=\frac{-\sin\left(\frac{xd}{c}\right)}{\frac{xd}{c}}h
	#x>r
	#x<-r
	# d = width_scale
	# h = height_scale
	# c = crater_scale
	# r = radius
	return (
		-1.0 * sin(x * width_scale / crater_scale) / (x * width_scale / crater_scale) * height_scale
	)


func get_top_layer_depth(x: float, radius: float, mid_relative_depth: float) -> float:
	#Top curve generation, needs an input intercept radius
	return cos(x / (2 * radius) / (3.14159265)) * mid_relative_depth


func load_saved_map() -> bool:
	var success: bool = false
	var saved_map_data: String = Helpers.load_data_from_file("user://saved_map.dat")
	if saved_map_data:
		var json: JSON = JSON.new()
		var error: int = json.parse(saved_map_data)
		if error != OK:
			printerr(
				"JSON Parse Error: ",
				json.get_error_message(),
				" in saved_map.dat at line ",
				json.get_error_line()
			)
			get_tree().quit()  # Quits the game due to bad server config data

		var loaded_map_data: Dictionary = json.data
		max_radius_in_tiles = loaded_map_data.max_radius_in_tiles
		for key: String in loaded_map_data.synced_data:
			current_data[str_to_var("Vector2i" + key)] = str_to_var(
				"Vector2i" + loaded_map_data.synced_data[key]
			)
		set_all_cell_data(current_data, 0)
		synced_data = current_data
		map_generated = true
		success = true
	return success


func regenerate_map() -> void:
	clear()
	current_data.clear()
	generate_map()


## Procedural world generation
func generate_map() -> void:
	var bottom_boundary_noise: FastNoiseLite = FastNoiseLite.new()

	bottom_boundary_noise.seed = randi()
	bottom_boundary_noise.noise_type = FastNoiseLite.TYPE_PERLIN

	var additional_depth_noise_scale: int = 30

	var barrier_depth: int = 75
	var minimum_top_depth: int = 60
	var random_depth_offset: int = 0

	var crater_generate_radius: int = 1909
	var width_scale: int = 8
	var height_scale: int = 1000
	var crater_scale: float = 2000.0
	var additional_waste_distance: int = 1000
	var fill_height: float = height_scale / 4.0

	if generate_simple_world:
		barrier_depth = 50
		crater_scale = 200
		additional_waste_distance = 10
		height_scale = 10
		crater_generate_radius = 400

	max_radius_in_tiles = crater_generate_radius + additional_waste_distance + 2

	var fill_intercept: float = crater_scale / float(width_scale) * 3.14159265

	var original_crater_generate_radius: int = crater_generate_radius
	while crater_generate_radius >= -original_crater_generate_radius:
		var radius: float = float(crater_generate_radius)
		if crater_generate_radius == 0:
			radius += 0.00001
		var depth: int = roundi(
			get_depth_function(
				float(radius), float(width_scale), float(height_scale), float(crater_scale)
			)
		)
		depth -= (
			roundi(bottom_boundary_noise.get_noise_1d(radius) * additional_depth_noise_scale)
			+ randi_range(0, random_depth_offset)
		)

		#Add bottom
		var top_depth: int = randi_range(0, random_depth_offset)
		for i: int in range(0, barrier_depth):
			current_data[Vector2i(roundi(radius), roundi(-(depth - i)))] = get_random_barrier_rock_tile()

		var in_core_radius: bool = radius >= -fill_intercept and radius <= fill_intercept
		#Add top layer
		for i: int in range(-top_depth, minimum_top_depth):
			var tile: Vector2i = Vector2i(roundi(radius), roundi(-(depth + i)))
			if in_core_radius:
				valid_resource_generation_tiles.append(tile)
			current_data[tile] = get_random_stone_tile()

		if in_core_radius:
			var local_fill_height: int = roundi(
				get_depth_function(
					float(radius), float(width_scale), float(fill_height), float(crater_scale)
				)
			)
			for i: int in range(depth + minimum_top_depth, local_fill_height):
				#print("A")

				var tile: Vector2i = Vector2i(roundi(radius), roundi(-(i)))
				valid_resource_generation_tiles.append(tile)
				current_data[tile] = get_random_stone_tile()

		crater_generate_radius -= 1

	var end_depth: float = get_depth_function(
		float(original_crater_generate_radius),
		float(width_scale),
		float(height_scale),
		float(crater_scale)
	)
	var original_waste_distance: int = additional_waste_distance
	while additional_waste_distance >= -original_waste_distance:
		var radius: int = original_crater_generate_radius + additional_waste_distance
		if additional_waste_distance < 0:
			radius = -original_crater_generate_radius + additional_waste_distance

		#Add bottom
		var depth: float = (
			end_depth
			- roundi(bottom_boundary_noise.get_noise_1d(radius) * additional_depth_noise_scale)
			+ randi_range(0, random_depth_offset)
		)
		for i: int in range(0, barrier_depth):
			current_data[Vector2i(radius, roundi(-(depth - i)))] = get_random_barrier_rock_tile()

		#Add top layer
		for i: int in range(0, minimum_top_depth):
			current_data[Vector2i(roundi(radius), roundi(-(depth + i)))] = get_random_stone_tile()

		additional_waste_distance -= 1

	#Generate top curve
	#Need intercept radius, approximate brute search or add inverse to depth function
	#Could replace arbitrary radius with peak height for smoother finish and less walls

	#Simple version
	'''
	var Diameter = 400
	var current_radius = Diameter / 2
	var radius = Diameter / 2

	var TopCenter = -10
	var BottomCenter = -130
	var TopEdge = 5
	var BottomEdge = -10

	while current_radius >= 0:
		var RadialMultiplier = 1.0 - cos(3.14159265 / radius * current_radius / 2.0)
		var TopHeight = roundi(
			(
				float(TopCenter)
				+ (
					(float(TopEdge) - float(TopCenter))
					/ float(radius)
					* float(current_radius)
					* float(RadialMultiplier)
				)
			)
		)
		var BottomHeight = roundi(
			(
				float(BottomCenter)
				+ (
					(float(BottomEdge) - float(BottomCenter))
					/ float(radius)
					* float(current_radius)
					* float(RadialMultiplier)
				)
			)
		)

		var BottomHeightA = BottomHeight + randi_range(-2, 2)
		var BottomHeightB = BottomHeight + randi_range(-2, 2)

		for Level in range(BottomHeightA, TopHeight, 1):
			if randf() > 0.98:
				current_data[Vector2i(current_radius, -Level)] = get_random_ore_tile()
			else:
				current_data[Vector2i(current_radius, -Level)] = get_random_stone_tile()

		for Level in range(BottomHeightB, TopHeight, 1):
			if randf() > 0.98:
				current_data[Vector2i(-current_radius, -Level)] = get_random_ore_tile()
			else:
				current_data[Vector2i(-current_radius, -Level)] = get_random_stone_tile()

		current_radius -= 1.0
	'''

	set_all_cell_data(current_data, 0)
	synced_data = current_data
	map_generated = true


## Gets a random valid stone tile ID from the atlas
func get_random_stone_tile() -> Vector2i:
	return Vector2i(randi_range(0, 9), 0)


func get_random_ore_tile() -> Vector2i:
	return Vector2i(randi_range(0, 9), 1)


func get_random_barrier_rock_tile() -> Vector2i:
	return Vector2i(randi_range(0, 9), 2)


func _process(delta: float) -> void:
	# Initial map data send/receive is rate limited by client ack, so no need to rate limit it otherwise.
	if Globals.is_server:
		if map_generated:
			chunk_and_send_initial_map_data_to_players()
	else:
		if not Globals.initial_map_load_finished:
			if map_download_finished:
				if not map_initialization_started:
					# Derpy method to update the overlay before running the set_all_cell_data function, which can be slow
					Network.update_pre_game_overlay.emit("Initializing map...")
					map_initialization_started = true
				else:
					if len(buffered_changes_received_from_server) > 0:
						for buffered_change: Dictionary in buffered_changes_received_from_server:
							for key: Vector2i in buffered_change.keys():
								synced_data[key] = buffered_change[key]
								current_data[key] = buffered_change[key]
					buffered_changes_received_from_server.clear()
					set_all_cell_data(current_data, 0)
					Globals.initial_map_load_finished = true
					visible = true
			else:
				re_request_initial_map_data_timer += delta
				if re_request_initial_map_data_timer > RE_REQUEST_INITIAL_MAP_DATA_TIMEOUT:
					re_request_initial_map_data_timer = 0.0  # Reset timer
					printerr("Timeout waiting for map data!")
					# Acknowledge the last packet again. If they lost the ACK, this will fix that,
					# If they sent us something newer, they will resend it.
					acknowledge_received_chunk.rpc_id(
						1, local_player_initial_map_data_last_chunk_id_received
					)

	# Rate limited stuff
	current_cycle_time += delta
	if current_cycle_time > SEND_FREQUENCY:
		if Globals.is_server:
			server_send_buffered_changes()
			if map_generated:
				if len(stored_player_inventory_drops):
					for key: int in stored_player_inventory_drops.keys():
						Globals.players[key].add_inventory_data.rpc(
							stored_player_inventory_drops[key]
						)
					stored_player_inventory_drops.clear()
		else:
			push_changed_data()
		current_cycle_time = 0.0


## Check for any buffered change data on the server (data received from clients and waiting to be sent), then chunk it and send it out to clients
func server_send_buffered_changes() -> void:
	if server_buffered_changes.size() > 0:
		var count: int = CHUNK_SIZE
		var chunked_data: Dictionary = {}
		while count > 0 and server_buffered_changes.size() > 0:
			chunked_data[server_buffered_changes.keys()[0]] = server_buffered_changes[
				server_buffered_changes.keys()[0]
			]
			server_buffered_changes.erase(server_buffered_changes.keys()[0])
			count -= 1
		server_send_changed_data.rpc(chunked_data)


## Set the tile map to the given values at given cells. Clears the tile map before doing so. Meant for complete map refreshes, not for incremental changes
func set_all_cell_data(data: Dictionary, layer: int) -> void:
	clear_layer(layer)
	for key: Vector2i in data.keys():
		set_cell_data(key, data[key], layer, 0, false)
	Network.update_pre_game_overlay.emit("Map initialization done.")


## Get the positions of every cell in the tile map
func get_cell_positions() -> Array:
	return synced_data.keys()


## Get the tile IDs of every cell in the tile map
func get_cell_ids(layer: int) -> Array:
	var ids: Array[Vector2i] = []
	var positions: Array[Vector2i] = get_used_cells(layer)

	for at_position: Vector2i in positions:
		ids.append(get_cell_atlas_coords(layer, at_position))
	return ids


## Requests a world state sync from the server, this is an initial request only sent when a client first joins
@rpc("any_peer", "call_remote", "reliable")
func request_initial_map_data() -> void:
	var player_id: int = multiplayer.get_remote_sender_id()

	server_side_per_player_initial_map_data[player_id] = {
		"synced_map_data_snapshot": [],
		"last_sent_stream_buffer": StreamPeerBuffer.new(),
		"last_sent_chunk_id": 0,
		"last_acknowledged_chunk_id": 0,
		"last_sent_map_data_index": -1,
		"finished_sending": false,
		"resend": false,
	}

	# It is required that we convert the Dictionary to an Array,
	# because we cannot iterate over a Dictionary in "chunks" in different frames,
	# because there is no defined order for a Dictionary.
	for key: Vector2i in synced_data:
		var value: Vector2i = synced_data[key]
		server_side_per_player_initial_map_data[player_id].synced_map_data_snapshot.append(
			[key, value]
		)


## Processes chunked initial states for each client that has requested a world state sync
func chunk_and_send_initial_map_data_to_players() -> void:
	if server_side_per_player_initial_map_data.size():
		for player_id: int in server_side_per_player_initial_map_data:
			if (
				server_side_per_player_initial_map_data[player_id].resend
				or (
					not server_side_per_player_initial_map_data[player_id].finished_sending
					and (
						(
							server_side_per_player_initial_map_data[player_id]
							. last_acknowledged_chunk_id
						)
						== server_side_per_player_initial_map_data[player_id].last_sent_chunk_id
					)
				)
			):
				if not server_side_per_player_initial_map_data[player_id].resend:
					var stream_data: StreamPeerBuffer = StreamPeerBuffer.new()
					while (
						stream_data.get_size() < MAP_TRANSFER_MAX_UNCOMPRESSED_DATA_SIZE
						and (
							(
								server_side_per_player_initial_map_data[player_id]
								. last_sent_map_data_index
							)
							< (
								len(
									(
										server_side_per_player_initial_map_data[player_id]
										. synced_map_data_snapshot
									)
								)
								- 1
							)
						)
					):
						var next_map_index: int = (
							(
								server_side_per_player_initial_map_data[player_id]
								. last_sent_map_data_index
							)
							+ 1
						)
						var map_entry: Array = (
							server_side_per_player_initial_map_data[player_id]
							. synced_map_data_snapshot[next_map_index]
						)
						stream_data.put_16(map_entry[0][0])
						stream_data.put_16(map_entry[0][1])
						stream_data.put_16(map_entry[1][0])
						stream_data.put_16(map_entry[1][1])
						server_side_per_player_initial_map_data[player_id].last_sent_map_data_index = next_map_index

					server_side_per_player_initial_map_data[player_id].last_sent_chunk_id += 1
					if (
						server_side_per_player_initial_map_data[player_id].last_sent_map_data_index
						>= (
							len(
								(
									server_side_per_player_initial_map_data[player_id]
									. synced_map_data_snapshot
								)
							)
							- 1
						)
					):
						server_side_per_player_initial_map_data[player_id].finished_sending = true

					server_side_per_player_initial_map_data[player_id].last_sent_stream_buffer = (
						stream_data.duplicate()
					)

				server_side_per_player_initial_map_data[player_id].resend = false

				var percent_complete: int = int(
					(
						float(
							(
								(
									server_side_per_player_initial_map_data[player_id]
									. last_sent_map_data_index
								)
								+ 1
							)
						)
						/ float(
							(
								server_side_per_player_initial_map_data[player_id]
								. synced_map_data_snapshot
								. size()
							)
						)
						* 100
					)
				)

				send_initial_map_data_chunk_to_client.rpc_id(
					player_id,
					server_side_per_player_initial_map_data[player_id].last_sent_chunk_id,
					(
						server_side_per_player_initial_map_data[player_id]
						. last_sent_stream_buffer
						. data_array
						. size()
					),
					(
						server_side_per_player_initial_map_data[player_id]
						. last_sent_stream_buffer
						. data_array
						. compress(MAP_TRANSFER_COMPRESSION_MODE)
					),
					percent_complete
				)

				server_side_per_player_initial_map_data[player_id].resend = false


@rpc("authority", "call_remote", "reliable")
func tell_client_initial_map_data_send_is_finished() -> void:
	map_download_finished = true


@rpc("any_peer", "call_remote", "reliable")
func acknowledge_received_chunk(chunk_id: int) -> void:
	var player_id: int = multiplayer.get_remote_sender_id()
	if chunk_id != server_side_per_player_initial_map_data[player_id].last_sent_chunk_id:
		server_side_per_player_initial_map_data[player_id].resend = true
		printerr(
			player_id,
			" requested a resend of map data chunk id ",
			server_side_per_player_initial_map_data[player_id].last_sent_chunk_id
		)
	else:
		server_side_per_player_initial_map_data[player_id].last_acknowledged_chunk_id = chunk_id
		if server_side_per_player_initial_map_data[player_id].finished_sending:
			tell_client_initial_map_data_send_is_finished.rpc_id(player_id)


## Send chunks of the world dat block to clients, used for initial world sync
@rpc("authority", "call_remote", "unreliable")
func send_initial_map_data_chunk_to_client(
	chunk_id: int, data_size: int, compressed_data: PackedByteArray, percent_complete: int
) -> void:
	re_request_initial_map_data_timer = 0.0  # Reset timer when we get data
	local_player_initial_map_data_last_chunk_id_received = chunk_id

	# Decompress data from stream buffer
	var data: StreamPeerBuffer = StreamPeerBuffer.new()
	data.data_array = compressed_data.decompress(data_size, MAP_TRANSFER_COMPRESSION_MODE)

	while data.get_available_bytes() >= 8:
		var map_position: Vector2i = Vector2i(data.get_16(), data.get_16())
		var id: Vector2i = Vector2i(data.get_16(), data.get_16())
		synced_data[map_position] = id
		current_data[map_position] = id
	acknowledge_received_chunk.rpc_id(1, chunk_id)
	Network.update_pre_game_overlay.emit("Loading map", percent_complete)


#Architecture plan:

#Players modify local data
#Push data to server, store buffered status
#Server receives push and overwrites local data
#Server pushes modifications to all clients
#Receiving client accepts changes
#Failed local state revision drops placed cells, drop items are not spawned until state change is confirmed

#Design Issues:
#Empty cells considered empty data, requires updating entire tile map for empty refresh (expensive?)
#Solution is to store remove tile changes as separate system


## Modify a cell from the client, checks for finished world load and buffers changes for server accordingly
func modify_cell(at_position: Vector2i, id: Vector2i) -> void:
	if !Globals.initial_map_load_finished:
		#Not allowed to modify map until first state received
		#Because current map is not trustworthy, not cleared on start so player doesn't fall through world immediately.
		return
	if changed_data.has(at_position):
		changed_data[at_position] = [changed_data[at_position][0], id]
	elif synced_data.has(at_position):
		changed_data[at_position] = [synced_data[at_position], id]
	else:
		changed_data[at_position] = [Vector2i(-1, -1), id]

	set_cell_data(at_position, id)


## Return the map tile position at a given world position
func get_cell_position_at_global_position(at_position: Vector2) -> Vector2i:
	return local_to_map(to_local(at_position))


## Return the tile data at a given map tile position
func get_cell_id_at_map_tile_position(at_position: Vector2i) -> Vector2i:
	# Use the correct data set based on client vs. server
	# current_data is the "best" reality for clients to work from and
	# synced_data is the "best" data for the server to work from
	var map_data_to_use: Dictionary
	if Globals.is_server:
		map_data_to_use = synced_data
	else:
		map_data_to_use = current_data
	if map_data_to_use.has(at_position):
		#print(map_data_to_use.values())
		#print(map_data_to_use[at_position])
		return map_data_to_use[at_position]
	# "Nothing", i.e. "air" is what "exists" at any position not listed in the map data
	return Vector2i(-1, -1)


## Return the tile data at a given world position
func get_cell_data_at_global_position(at_position: Vector2) -> Vector2i:
	var local_at_position: Vector2i = get_cell_position_at_global_position(at_position)
	return get_cell_id_at_map_tile_position(local_at_position)


## Return the global position of a map cell given its map local position
func get_global_position_at_map_local_position(at_position: Vector2i) -> Vector2:
	return to_global(map_to_local(at_position))


## Place air at a position
func mine_cell_at_position(at_position: Vector2) -> void:
	var compensated_position: Vector2i = local_to_map(to_local(at_position))
	if (
		current_data.has(compensated_position)
		and (current_data[compensated_position] != Vector2i(-1, -1))
	):
		if Globals.get_is_cell_mineable(current_data[compensated_position]):
			tile_modification_particles_controller.destroy_cell(
				compensated_position, current_data[compensated_position]
			)
			modify_cell(compensated_position, Vector2i(-1, -1))
			Globals.player_has_done.mine_a_block = true


func highlight_cell_at_global_position(at_position: Vector2, color: Color = Color.GREEN) -> void:
	var at_cell_position: Vector2i = get_cell_position_at_global_position(at_position)
	var cell_global_position: Vector2 = get_global_position_at_map_local_position(at_cell_position)
	$Drawing.rectangles_to_draw[Rect2(cell_global_position.x - 8, cell_global_position.y - 8, 16, 16)] = {
	}
	$Drawing.rectangles_to_draw[Rect2(cell_global_position.x - 8, cell_global_position.y - 8, 16, 16)].color = color
	$Drawing.update_draw = true


func highlight_cell_at_map_position(at_cell_position: Vector2, color: Color = Color.GREEN) -> void:
	var cell_global_position: Vector2 = get_global_position_at_map_local_position(at_cell_position)
	$Drawing.rectangles_to_draw[Rect2(cell_global_position.x - 8, cell_global_position.y - 8, 16, 16)] = {
	}
	$Drawing.rectangles_to_draw[Rect2(cell_global_position.x - 8, cell_global_position.y - 8, 16, 16)].color = color
	$Drawing.update_draw = true


func draw_line_on_map(
	from_position: Vector2, to_position: Vector2, color: Color = Color.GREEN
) -> void:
	$Drawing.lines_to_draw[str(from_position.x, "-", from_position.y, "-", to_position.x, "-", to_position.y)] = {
	}
	$Drawing.lines_to_draw[str(from_position.x, "-", from_position.y, "-", to_position.x, "-", to_position.y)].from = from_position
	$Drawing.lines_to_draw[str(from_position.x, "-", from_position.y, "-", to_position.x, "-", to_position.y)].to = to_position
	$Drawing.lines_to_draw[str(from_position.x, "-", from_position.y, "-", to_position.x, "-", to_position.y)].color = color
	$Drawing.update_draw = true


## Place a standard piece of stone at a position : TEST TEMP
func place_cell_at_position(at_position: Vector2) -> void:
	var at_cell_position: Vector2i = get_cell_position_at_global_position(at_position)
	if !Globals.get_is_cell_mineable(get_cell_id_at_map_tile_position(at_cell_position)):
		return
	var adjacent_cell_contents: Array = [
		get_cell_id_at_map_tile_position(Vector2i(at_cell_position.x, at_cell_position.y - 1)),
		get_cell_id_at_map_tile_position(Vector2i(at_cell_position.x, at_cell_position.y + 1)),
		get_cell_id_at_map_tile_position(Vector2i(at_cell_position.x - 1, at_cell_position.y)),
		get_cell_id_at_map_tile_position(Vector2i(at_cell_position.x + 1, at_cell_position.y)),
	]
	var can_place_cell: bool = false
	for cell_content: Vector2i in adjacent_cell_contents:
		if cell_content != Vector2i(-1, -1):
			can_place_cell = true
	if can_place_cell:
		modify_cell(local_to_map(to_local(at_position)), get_random_stone_tile())
		Globals.player_has_done.place_a_block = true


## Set the current data of a cell to a given value
func set_cell_data(
	at_position: Vector2i,
	id: Vector2i,
	layer: int = 0,
	source_id: int = 0,
	update_current_data: bool = true
) -> void:
	if update_current_data:
		current_data[at_position] = id
	set_cell(layer, at_position, source_id, id)
	var cells_to_check: Array = get_surrounding_cells(at_position)
	cells_to_check.append(at_position)
	for cell_position: Vector2i in cells_to_check:
		var cell_source_id: int = get_cell_source_id(layer, cell_position)
		if cell_source_id > -1:
			var cell_atlas_coords: Vector2i = get_cell_atlas_coords(layer, cell_position)
			var should_have_collider: bool = false
			for surrounding_cell: Vector2i in get_surrounding_cells(cell_position):
				if get_cell_source_id(layer, surrounding_cell) == -1:
					should_have_collider = true
			# TODO: source_id is hard coded here, assuming 0 has colliders and 1 does not.
			if should_have_collider and cell_source_id > 0:
				set_cell(layer, cell_position, 0, cell_atlas_coords)
			elif not should_have_collider and cell_source_id < 1:
				set_cell(layer, cell_position, 1, cell_atlas_coords)


## Push change data stored on the client to the server, if there is any
## Still need to add chunking to this process right here
func push_changed_data() -> void:
	if changed_data.size() > 0:
		transfer_changed_map_data_to_server.rpc_id(1, changed_data)
		changed_data.clear()


## Sends changes from the client to the server to be processed
@rpc("any_peer", "call_remote", "reliable")
func transfer_changed_map_data_to_server(map_data: Dictionary) -> void:
	var player_id: int = multiplayer.get_remote_sender_id()
	var tiles_to_update: Dictionary = {}
	for key: Vector2i in map_data.keys():
		if not synced_data.has(key) or synced_data[key] == map_data[key][0]:
			server_buffered_changes[key] = map_data[key][1]
			synced_data[key] = map_data[key][1]
			tiles_to_update[key] = map_data[key][1]

			if map_data[key][0].y > -1:
				if not stored_player_inventory_drops.has(player_id):
					stored_player_inventory_drops[player_id] = {}
				if stored_player_inventory_drops[player_id].has(map_data[key][0].y):
					stored_player_inventory_drops[player_id][map_data[key][0].y] += 1
				else:
					stored_player_inventory_drops[player_id][map_data[key][0].y] = 1
	serve_update_tiles_from_given_data(tiles_to_update)


func serve_update_tiles_from_given_data(tiles_to_update: Dictionary) -> void:
	if tiles_to_update.size() > 0:
		for key: Vector2i in tiles_to_update.keys():
			set_cell_data(key, tiles_to_update[key], 0, 0, false)


## Sends changes from the server to clients
@rpc("authority", "call_remote", "reliable")
func server_send_changed_data(data: Dictionary) -> void:
	if !Globals.initial_map_load_finished:
		#Store changes and process after the maps has been fully loaded
		buffered_changes_received_from_server.append(data)
		return
	if Globals.is_server:
		return
	for key: Vector2i in data.keys():
		if (
			current_data.has(key)
			and current_data[key] != data[key]
			and current_data.has(key)
			and (current_data[key] != Vector2i(-1, -1))
		):
			tile_modification_particles_controller.destroy_cell(key, data[key])
		synced_data[key] = data[key]
		current_data[key] = data[key]
		update_cell_from_current(key)


## Updates a cells tile from current data
func update_cell_from_current(at_position: Vector2i) -> void:
	set_cell_data(at_position, current_data[at_position], 0, 0, false)


@rpc("any_peer", "call_local", "reliable")
func save_map() -> void:
	Helpers.log_print("Save Map!")
	Helpers.save_data_to_file(
		"user://saved_map.dat",
		JSON.stringify({"max_radius_in_tiles": max_radius_in_tiles, "synced_data": synced_data})
	)


func check_tile_location_and_surroundings(at_position: Vector2i) -> Globals.MapTileSet:
	var cell_position_at_position: Vector2i = (
		Globals.world_map.get_cell_position_at_global_position(at_position)
	)

	var return_data: Globals.MapTileSet = Globals.MapTileSet.new()
	print(return_data.tile_list.size())
	return_data.all_tiles_are_empty = true

	# Find out what tiles exist at the requested position
	for x_position: int in range(0, 1):
		for y_position: int in range(0, 1):
			return_data.tile_list.append(
				Vector2i(
					cell_position_at_position.x + x_position,
					cell_position_at_position.y + y_position
				)
			)
