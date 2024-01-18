extends TileMap

var MapGenerated: bool = false

#No longer using arrays, read/write requires an indexing system which negates the performance benefit of using array index overlap as link. Reading Positions and IDs separately may be faster if staggered separately but can be added later and merged into local dictionaries.

#Last change from server, considered highest authority on accuracy
var SyncedData: Dictionary = {}
#Current map state, presumably faster than reading tilemap again
var CurrentData: Dictionary = {}
#Local modifications buffered until next sync cycle
var ChangedData: Dictionary = {}

# CurrentData is the "best" reality for clients to work from and
# SyncedData is the "best" data for the server to work from

#NOTE : Godot passes all dictionaries by reference, remember that.

const ChunkSize: int = 4000

var IsServer: bool = false

var ServerDataChanged: bool = false

var current_cycle_time: float = 0.0
const send_frequency: float = 0.1
const re_request_initial_map_data_timeout: float = 2.0
var re_request_initial_map_data_timer: float = 0.0

var local_player_initial_map_data_current_chunk_id: int = 0

#Changes the server has received and accepted, and is waiting to send back to all clients later
var ServerBufferedChanges: Dictionary = {}

var StoredPlayerInventoryDrops: Dictionary = {}

var BufferedChangesReceivedFromServer: Array[Dictionary] = []

var server_side_per_player_initial_map_data: Dictionary = {}

@export var TileModificationParticlesController: CPUParticles2D


func _ready() -> void:
	# Without this, sending a StreamPeerBuffer over an RPC generates the error
	# "Cannot convert argument 1 from Object to Object" on the receiving end
	# and fails.
	# https://github.com/godotengine/godot/issues/82718
	multiplayer.allow_object_decoding = true

	IsServer = Globals.is_server

	if IsServer:
		GenerateMap()
		Globals.initial_map_load_finished = true
	else:
		request_initial_map_data.rpc_id(1)

	Globals.WorldMap = self


func GetDepthFunction(x: float, WidthScale: float, HeightScale: float, CraterScale: float) -> float:
	return -1.0 * sin(x * WidthScale / CraterScale) / (x * WidthScale / CraterScale) * HeightScale


## Procedural world generation
func GenerateMap() -> void:
	# Desmos Formula:
	#y=\frac{-\sin\left(\frac{xd}{c}\right)}{\frac{xd}{c}}h
	#x>r
	#x<r
	# d = WidthScale
	# h = HeightScale
	# c = CraterScale
	# r = radius

	var Radius: int = 1909
	var WidthScale: int = 8
	var HeightScale: int = 1000
	var CraterScale: float = 2000.0

	while Radius > 0:
		var Depth: int = roundi(
			GetDepthFunction(
				float(Radius), float(WidthScale), float(HeightScale), float(CraterScale)
			)
		)
		for i: int in range(0, 20):
			CurrentData[Vector2i(Radius, -(Depth + i))] = GetRandomStoneTile()
			CurrentData[Vector2i(-Radius, -(Depth + i))] = GetRandomStoneTile()
			Depth += 1

		Radius -= 1

	#New version

	#Simple version
	'''
	var Diameter = 400
	var CurrentRadius = Diameter / 2
	var Radius = Diameter / 2

	var TopCenter = -10
	var BottomCenter = -130
	var TopEdge = 5
	var BottomEdge = -10

	while CurrentRadius >= 0:
		var RadialMultiplier = 1.0 - cos(3.14159265 / Radius * CurrentRadius / 2.0)
		var TopHeight = roundi(
			(
				float(TopCenter)
				+ (
					(float(TopEdge) - float(TopCenter))
					/ float(Radius)
					* float(CurrentRadius)
					* float(RadialMultiplier)
				)
			)
		)
		var BottomHeight = roundi(
			(
				float(BottomCenter)
				+ (
					(float(BottomEdge) - float(BottomCenter))
					/ float(Radius)
					* float(CurrentRadius)
					* float(RadialMultiplier)
				)
			)
		)

		var BottomHeightA = BottomHeight + randi_range(-2, 2)
		var BottomHeightB = BottomHeight + randi_range(-2, 2)

		for Level in range(BottomHeightA, TopHeight, 1):
			if randf() > 0.98:
				CurrentData[Vector2i(CurrentRadius, -Level)] = GetRandomOreTile()
			else:
				CurrentData[Vector2i(CurrentRadius, -Level)] = GetRandomStoneTile()

		for Level in range(BottomHeightB, TopHeight, 1):
			if randf() > 0.98:
				CurrentData[Vector2i(-CurrentRadius, -Level)] = GetRandomOreTile()
			else:
				CurrentData[Vector2i(-CurrentRadius, -Level)] = GetRandomStoneTile()

		CurrentRadius -= 1.0
	'''

	'''
	CurrentData[Vector2i(0, 0)] = GetRandomOreTile()
	CurrentData[Vector2i(1, 0)] = GetRandomOreTile()
	CurrentData[Vector2i(0, 1)] = GetRandomOreTile()
	CurrentData[Vector2i(1, 1)] = GetRandomOreTile()
	CurrentData[Vector2i(-1, 1)] = GetRandomOreTile()
	'''

	SetAllCellData(CurrentData, 0)
	SyncedData = CurrentData

	# Save initial map "size" before flagging it as "ready"
	# TODO: Timestamp this and turn it into a function that can be called again for updating
	for map_coordinate: Vector2i in CurrentData:
		if map_coordinate.x < Globals.map_edges.min.x:
			Globals.map_edges.min.x = map_coordinate.x
		if map_coordinate.x > Globals.map_edges.max.x:
			Globals.map_edges.max.x = map_coordinate.x
		if map_coordinate.y < Globals.map_edges.min.x:
			Globals.map_edges.min.x = map_coordinate.y
		if map_coordinate.y > Globals.map_edges.max.y:
			Globals.map_edges.max.y = map_coordinate.y

	MapGenerated = true

	'''
	# TileModificationParticlesController.DestroyCells([Vector2i(0, 0)],[CurrentData[Vector2i(0, 0)]])

	TileModificationParticlesController.DestroyCells([Vector2i(0, 0),Vector2i(1, 0),Vector2i(0, 1),Vector2i(1, 1),Vector2i(-1, 1)],
	[CurrentData[Vector2i(0, 0)],CurrentData[Vector2i(1, 0)],CurrentData[Vector2i(0, 1)],CurrentData[Vector2i(1, 1)],CurrentData[Vector2i(-1, 1)]])
	'''


## Gets a random valid stone tile ID from the atlas
func GetRandomStoneTile() -> Vector2i:
	return Vector2i(randi_range(0, 9), 0)


func GetRandomOreTile() -> Vector2i:
	return Vector2i(randi_range(0, 9), 1)


func _process(delta: float) -> void:
	current_cycle_time += delta
	if current_cycle_time > send_frequency:
		if Globals.is_server:
			ServerSendBufferedChanges()
			if MapGenerated:
				chunk_and_send_initial_map_data_to_players()

				if len(StoredPlayerInventoryDrops):
					for Key: int in StoredPlayerInventoryDrops.keys():
						Globals.Players[Key].AddInventoryData.rpc(StoredPlayerInventoryDrops[Key])
					StoredPlayerInventoryDrops.clear()
		else:
			PushChangedData()
			if not Globals.initial_map_load_finished:
				re_request_initial_map_data_timer += delta
				if re_request_initial_map_data_timer > re_request_initial_map_data_timeout:
					re_request_initial_map_data_timer = 0.0  # Reset timer
					printerr("Timeout waiting for map data!")
					# Acknowledge the last packet again. If they lost the ACK, this will fix that,
					# If they sent us something newer, they will resend it.
					acknowledge_received_chunk.rpc_id(
						1, local_player_initial_map_data_current_chunk_id
					)
		current_cycle_time = 0.0

	if IsServer and ServerDataChanged:
		ServerDataChanged = false
		SetAllCellData(SyncedData, 0)


## Check for any buffered change data on the server (data received from clients and waiting to be sent), then chunk it and send it out to clients
func ServerSendBufferedChanges() -> void:
	if len(ServerBufferedChanges.keys()) > 0:
		var Count: int = ChunkSize
		var ChunkedData: Dictionary = {}
		while Count > 0 and len(ServerBufferedChanges.keys()) > 0:
			ChunkedData[ServerBufferedChanges.keys()[0]] = ServerBufferedChanges[
				ServerBufferedChanges.keys()[0]
			]
			ServerBufferedChanges.erase(ServerBufferedChanges.keys()[0])
			Count -= 1
		ServerSendChangedData.rpc(ChunkedData)


## Set the tile map to the given values at given cells. Clears the tile map before doing so. Meant for complete map refreshes, not for incremental changes
func SetAllCellData(Data: Dictionary, Layer: int) -> void:
	clear_layer(Layer)
	for Key: Vector2i in Data.keys():
		set_cell(Layer, Key, 0, Data[Key])


## Get the positions of every cell in the tile map
func GetCellPositions(Layer: int) -> Array[Vector2i]:
	var Positions: Array[Vector2i] = get_used_cells(Layer)
	return Positions


## Get the tile IDs of every cell in the tile map
func GetCellIDs(Layer: int) -> Array:
	var IDs: Array[Vector2i] = []
	var Positions: Array[Vector2i] = get_used_cells(Layer)

	for Position: Vector2i in Positions:
		IDs.append(get_cell_atlas_coords(Layer, Position))
	return IDs


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
		"received_ack_for_finish": false,
		"resend": false,
	}

	# It is required that we convert the Dictionary to an Array,
	# because we cannot iterate over a Dictionary in "chunks" in different frames,
	# because there is no defined order for a Dictionary.
	for key: Vector2i in SyncedData:
		var value: Vector2i = SyncedData[key]
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
					var StreamData: StreamPeerBuffer = StreamPeerBuffer.new()

					while (
						StreamData.get_size() < 64000  # Should this relate to the setting used in network_websocket?
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
						StreamData.put_16(map_entry[0][0])
						StreamData.put_16(map_entry[0][1])
						StreamData.put_16(map_entry[1][0])
						StreamData.put_16(map_entry[1][1])
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
						StreamData.duplicate()
					)

				server_side_per_player_initial_map_data[player_id].resend = false

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
						. compress()
					),
					server_side_per_player_initial_map_data[player_id].resend
				)
				server_side_per_player_initial_map_data[player_id].resend = false


@rpc("authority", "call_remote", "reliable")
func tell_client_initial_map_data_send_is_finished() -> void:
	if len(BufferedChangesReceivedFromServer) > 0:
		for BufferedChange: Dictionary in BufferedChangesReceivedFromServer:
			for Key: Vector2i in BufferedChange.keys():
				SyncedData[Key] = BufferedChange[Key]
				CurrentData[Key] = BufferedChange[Key]
	BufferedChangesReceivedFromServer.clear()

	Globals.initial_map_load_finished = true


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
	chunk_id: int, data_size: int, compressed_data: PackedByteArray, resend: bool
) -> void:
	re_request_initial_map_data_timer = 0.0  # Reset timer when we get data
	if not resend:
		local_player_initial_map_data_current_chunk_id += 1

	if local_player_initial_map_data_current_chunk_id != chunk_id:
		printerr(
			"New System Packet ID mismatch! Possibly missed packet! Client chunk_id ",
			local_player_initial_map_data_current_chunk_id,
			" != Server chunk_id ",
			chunk_id
		)
		# TODO: Tell the server to re-send
		return

	# Decompress data from stream buffer
	var data: StreamPeerBuffer = StreamPeerBuffer.new()
	data.data_array = compressed_data.decompress(data_size)

	while data.get_available_bytes() >= 8:
		var map_position: Vector2i = Vector2i(data.get_16(), data.get_16())
		var id: Vector2i = Vector2i(data.get_16(), data.get_16())
		SyncedData[map_position] = id
		CurrentData[map_position] = id
	SetAllCellData(CurrentData, 0)
	acknowledge_received_chunk.rpc_id(1, local_player_initial_map_data_current_chunk_id)


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
func ModifyCell(Position: Vector2i, ID: Vector2i) -> void:
	if !Globals.initial_map_load_finished:
		#Not allowed to modify map until first state received
		#Because current map is not trustworthy, not cleared on start so player doesn't fall through world immediately.
		return
	if Position in ChangedData.keys():
		ChangedData[Position] = [ChangedData[Position][0], ID]
	elif SyncedData.has(Position):
		ChangedData[Position] = [SyncedData[Position], ID]
	else:
		ChangedData[Position] = [Vector2i(-1, -1), ID]

	SetCellData(Position, ID)


## Return the map tile position at a given world position
func get_cell_position_at_global_position(at_position: Vector2) -> Vector2i:
	return local_to_map(to_local(at_position))


## Return the tile data at a given map tile position
func get_cell_data_at_map_local_position(at_position: Vector2i) -> Vector2i:
	# Use the correct data set based on client vs. server
	# CurrentData is the "best" reality for clients to work from and
	# SyncedData is the "best" data for the server to work from
	var map_data_to_use: Dictionary
	if Globals.is_server:
		map_data_to_use = SyncedData
	else:
		map_data_to_use = CurrentData
	if map_data_to_use.has(at_position):
		return map_data_to_use[at_position]
	# "Nothing", i.e. "air" is what "exists" at any position not listed in the map data
	return Vector2i(-1, -1)


## Return the tile data at a given world position
func get_cell_data_at_global_position(at_position: Vector2) -> Vector2i:
	var local_at_position: Vector2i = get_cell_position_at_global_position(at_position)
	return get_cell_data_at_map_local_position(local_at_position)


## Return the global position of a map cell given its map local position
func get_global_position_at_map_local_position(at_position: Vector2i) -> Vector2:
	return to_global(map_to_local(at_position))


## Place air at a position : TEST TEMP
func MineCellAtPosition(Position: Vector2) -> void:
	var CompensatedPosition: Vector2i = local_to_map(to_local(Position))
	if (
		(CompensatedPosition in CurrentData.keys())
		and (CurrentData[CompensatedPosition] != Vector2i(-1, -1))
	):
		TileModificationParticlesController.DestroyCell(
			CompensatedPosition, CurrentData[CompensatedPosition]
		)
	ModifyCell(CompensatedPosition, Vector2i(-1, -1))


## Place a standard piece of stone at a position : TEST TEMP
func PlaceCellAtPosition(Position: Vector2) -> void:
	ModifyCell(local_to_map(to_local(Position)), GetRandomStoneTile())


## Set the current data of a cell to a given value
func SetCellData(Position: Vector2i, ID: Vector2i) -> void:
	CurrentData[Position] = ID
	set_cell(0, Position, 0, ID)


## Push change data stored on the client to the server, if there is any
## Still need to add chunking to this process right here
func PushChangedData() -> void:
	if len(ChangedData.keys()) > 0:
		RPCSendChangedData.rpc(ChangedData)
		ChangedData.clear()


## Sends changes from the client to the server to be processed
@rpc("any_peer", "call_remote", "reliable")
func RPCSendChangedData(Data: Dictionary) -> void:
	if IsServer:
		var player_id: int = multiplayer.get_remote_sender_id()
		for Key: Vector2i in Data.keys():
			if not SyncedData.has(Key) or SyncedData[Key] == Data[Key][0]:
				ServerBufferedChanges[Key] = Data[Key][1]
				SyncedData[Key] = Data[Key][1]

				if Data[Key][0].y > -1:
					if player_id not in StoredPlayerInventoryDrops.keys():
						StoredPlayerInventoryDrops[player_id] = {}
					if Data[Key][0].y in StoredPlayerInventoryDrops[player_id].keys():
						StoredPlayerInventoryDrops[player_id][Data[Key][0].y] += 1
					else:
						StoredPlayerInventoryDrops[player_id][Data[Key][0].y] = 1

		ServerDataChanged = true


## Sends changes from the server to clients
@rpc("authority", "call_remote", "reliable")
func ServerSendChangedData(Data: Dictionary) -> void:
	if !Globals.initial_map_load_finished:
		#Store changes and process after the maps has been fully loaded
		BufferedChangesReceivedFromServer.append(Data)
		return
	if IsServer:
		return
	for Key: Vector2i in Data.keys():
		if (
			(CurrentData[Key] != Data[Key])
			and (Key in CurrentData.keys())
			and (CurrentData[Key] != Vector2i(-1, -1))
		):
			TileModificationParticlesController.DestroyCell(Key, Data[Key])
		SyncedData[Key] = Data[Key]
		CurrentData[Key] = Data[Key]
		UpdateCellFromCurrent(Key)


## Updates a cells tile from current data
func UpdateCellFromCurrent(Position: Vector2i) -> void:
	set_cell(0, Position, 0, CurrentData[Position])
