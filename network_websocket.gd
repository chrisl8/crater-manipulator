extends Node

signal reset
signal close_pre_game_overlay
signal update_pre_game_overlay

enum Message { PLAYER_JOINED, PLAYER_TOKEN, SHUTDOWN_SERVER }

var ready_to_connect: bool = false
var peers: Dictionary
var peer_count: int = -1
var peers_have_connected: bool = false
var network_initialized: bool = false
var game_scene_initialize_in_progress: bool = false
var game_scene_initialized: bool = false
var network_connection_initiated: bool = false

var player_character_template: PackedScene = preload("res://player/player.tscn")
var map: PackedScene = preload("res://items/map/map.tscn")

var websocket_multiplayer_peer: WebSocketMultiplayerPeer
var uuid_util: Resource = preload("res://addons/uuid/uuid.gd")

var ServerCamera: PackedScene = preload("res://server_camera/server_camera.tscn")


func _process(_delta: float) -> void:
	if not ready_to_connect:
		return

	if not network_connection_initiated:
		network_connection_initiated = true
		init_network()

	if not network_initialized:
		return

	if peers.size() != peer_count:
		peer_count = peers.size()
		if peer_count > 0:
			peers_have_connected = true
		Helpers.log_print(str("New peer count is: ", peer_count), "cyan")

	if not Globals.is_server:
		# Only server proceeds past this point,
		# adding and removing objects, etc.
		return

	# In Debug mode, exit server if everyone disconnects in order to speed up debugging sessions (less windows to close)
	if (
		OS.is_debug_build()
		and peers_have_connected
		and peer_count < 1
		and !Globals.shutdown_in_progress
	):
		Helpers.log_print(
			"Closing server due to all clients disconnecting and this running in Debug mode.",
			"cyan"
		)
		Helpers.quit_gracefully()

	# Initialize the Map if it isn't yet
	if not game_scene_initialized:
		if not game_scene_initialize_in_progress:
			game_scene_initialize_in_progress = true
			load_level.call_deferred(map)
		elif get_node_or_null("../Main/Map/game_scene"):
			game_scene_initialized = true
			close_pre_game_overlay.emit()
		return

	# NOTE: As of 1/9/2024 Spawner does absolutely nothing, but maybe it will someday?
	Spawner.things()


func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected_to_server)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)


func load_level(scene: PackedScene) -> void:
	var level_parent: Node = get_tree().get_root().get_node("Main/Map")
	for c: Node in level_parent.get_children():
		level_parent.remove_child(c)
		c.queue_free()
	var game_scene: Node = scene.instantiate()
	game_scene.name = "game_scene"
	level_parent.add_child(game_scene)
	level_parent.add_child(ServerCamera.instantiate())


func generate_jwt(secret: String, player_uuid: String) -> String:
	var jwt_algorithm: JWTAlgorithm = JWTAlgorithm.HS256.new(secret)
	var jwt_builder: JWTBuilder = (
		JWT
		. create()
		. with_issued_at(int(Time.get_unix_time_from_system()))
		. with_expires_at(int(Time.get_unix_time_from_system()) + 60 * 60 * 24 * 365)
		. with_issuer("Space Game")
		. with_payload({"uuid": player_uuid})
	)
	var jwt: String = jwt_builder.sign(jwt_algorithm)
	return jwt


func validate_and_decode_jwt(secret: String, jwt: String) -> Dictionary:
	var content: Dictionary = {}
	var jwt_algorithm: JWTAlgorithm = JWTAlgorithm.HS256.new(secret)
	var jwt_verifier: JWTVerifier = JWT.require(jwt_algorithm).with_issuer("Space Game").build()
	if jwt_verifier.verify(jwt) == JWTVerifier.JWTExceptions.OK:
		var jwt_decoder: JWTDecoder = JWT.decode(jwt)
		content = jwt_decoder.get_claims()
	else:
		printerr(jwt_verifier.exception)
	return content


func _peer_connected(id: int) -> void:
	Helpers.log_print(str("Peer ", id, " connected."), "cyan")
	peers[id] = {}


func _peer_disconnected(id: int) -> void:
	Helpers.log_print(str("Peer ", id, " Disconnected."), "cyan")
	var player_uuid: String = ""
	if peers.has(id):
		if peers[id].has("uuid"):
			player_uuid = peers[id]["uuid"]
		peers.erase(id)
	if not Globals.is_server:
		return

	var player_spawner_node: Node = get_node_or_null("../Main/Players")
	if player_spawner_node and player_spawner_node.has_node(str(id)):
		var player: Node = player_spawner_node.get_node(str(id))
		print_rich(
			"[color=blue]",
			"Server: Player ",
			id,
			" ",
			player_uuid,
			" disconnected while at position ",
			player.position,
			" rotation ",
			player.rotation,
			"[/color]"
		)
		if (
			player_uuid != ""
			and player.position.x != NAN
			and player.position.y != NAN
			and player.rotation != NAN
		):
			Globals.player_save_data[player_uuid]["position"] = {
				"x": player.position.x, "y": player.position.y
			}
			Globals.player_save_data[player_uuid]["rotation"] = player.rotation
			Helpers.save_server_player_save_data_to_file()
		player.queue_free()


func player_save_data_filename() -> String:
	var file_name: String = "user://save_game.dat"
	if Globals.local_debug_instance_number > -1:
		file_name = str("user://save_game_", Globals.local_debug_instance_number, ".dat")
	return file_name


@rpc("any_peer", "call_remote", "reliable")
func update_remote_pre_game_overlay_message(message: String) -> void:
	update_pre_game_overlay.emit(message)


func _connected_to_server() -> void:
	Globals.has_connected_once = true
	Helpers.log_print("I connected to the server!", "cyan")
	if Globals.shutdown_server:
		print_rich("[color=blue]Sending SHUTDOWN_SERVER message.[/color]")
		send_data_to(1, Message.SHUTDOWN_SERVER, Globals.server_config["server_password"])
		Helpers.quit_gracefully()
		return

	#TODO: Testing data read/write
	var saved_player_data: String = Helpers.load_data_from_file(player_save_data_filename())

	# Wait for map data to load from server before initiating player spawn
	while not Globals.initial_map_load_finished:
		await get_tree().create_timer(0.5).timeout

	# Server does not spawn our player until we send a "join" message
	send_data_to(1, Message.PLAYER_JOINED, saved_player_data)


func _connection_failed() -> void:
	Helpers.log_print("My connection failed. =(", "cyan")
	Globals.connection_failed_message = "Connection Failed!"
	reset_connection()


func _server_disconnected() -> void:
	Helpers.log_print("Server Disconnected", "cyan")
	Globals.connection_failed_message = "Connection Interrupted!"
	reset_connection()


func shutdown_server() -> void:
	if Globals.is_server and peers.size() > 0:
		for key: int in peers:
			print_rich("[color=blue]Telling ", key, " to disconnect[/color]")
			websocket_multiplayer_peer.disconnect_peer(key)


func reset_connection() -> void:
	Helpers.log_print("Resetting Connection", "cyan")
	ready_to_connect = false
	network_connection_initiated = false
	network_initialized = false
	game_scene_initialized = false
	game_scene_initialize_in_progress = false
	multiplayer.multiplayer_peer = null
	websocket_multiplayer_peer = null
	peer_count = -1
	Globals.user_name = ""
	peers.clear()
	var retry_timeout: int = 5
	if OS.is_debug_build():
		retry_timeout = 1
	reset.emit(retry_timeout)


func init_network() -> void:
	Helpers.log_print("Init Network", "cyan")
	websocket_multiplayer_peer = WebSocketMultiplayerPeer.new()
	# This is a client/server setup, NOT a Mesh.
	if Globals.is_server:
		websocket_multiplayer_peer.create_server(9091)
	else:
		var error: int = websocket_multiplayer_peer.create_client(Globals.url)  # WebSocket
		if error:
			Helpers.log_print(str("Websocket Error: ", error), "cyan")
	get_tree().get_multiplayer().multiplayer_peer = websocket_multiplayer_peer
	# In theory these can help, but I have not been able to prove that they have any affect:
	#websocket_multiplayer_peer.inbound_buffer_size = 16777216
	#websocket_multiplayer_peer.outbound_buffer_size = 16777216
	network_initialized = true


func send_data_to(id: int, msg_type: Message, data: String) -> void:
	var send_data: String = (
		JSON
		. stringify(
			{
				"type": msg_type,
				"data": data,
			}
		)
	)
	rpc_id(id, "data_received", send_data)


@rpc("any_peer")
func data_received(data: String) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()

	var json: JSON = JSON.new()
	var error: int = json.parse(data)
	if error != OK:
		printerr(
			"JSON Parse Error: ",
			json.get_error_message(),
			" in ",
			data,
			" at line ",
			json.get_error_line(),
			" from ",
			sender_id
		)
		return

	var parsed_message: Variant = json.data
	if (
		typeof(parsed_message) != TYPE_DICTIONARY
		or not parsed_message.has("type")
		or not parsed_message.has("data")
	):
		printerr("Data error in: ", parsed_message, " from ", sender_id)
		return

	if parsed_message.type == Message.SHUTDOWN_SERVER:
		if parsed_message.data == Globals.server_config["server_password"]:
			print_rich("[color=blue]Server shutdown requested from client ", sender_id, "[/color]")
			Helpers.quit_gracefully()
		else:
			printerr("Client ", sender_id, " attempted to shut down server with invalid password.")
		return

	if parsed_message.type == Message.PLAYER_JOINED:
		player_joined(sender_id, parsed_message.data)
		return

	if parsed_message.type == Message.PLAYER_TOKEN:
		Helpers.save_data_to_file(player_save_data_filename(), parsed_message.data)
		close_pre_game_overlay.emit()
		return

	printerr(
		"Unknown Message Type ", parsed_message.type, " in: ", parsed_message, " from ", sender_id
	)


## Check player's position and surrounding area to ensure it is clear for spawning
func check_location_and_surroundings(at_position: Vector2) -> bool:
	var cell_position_at_player_potential_position: Vector2i = (
		Globals.WorldMap.get_cell_position_at_global_position(at_position)
	)

	var all_cell_positions_to_clear_for_player: Array[Vector2i] = []

	var starting_point: Vector2i = Vector2i(
		cell_position_at_player_potential_position.x - 1,
		cell_position_at_player_potential_position.y - 3
	)

	# Find out what tiles exist at the player's intended position
	for x_position: int in range(0, 2):
		for y_position: int in range(0, 3):
			all_cell_positions_to_clear_for_player.append(
				Vector2i(starting_point.x + x_position, starting_point.y + y_position)
			)

	var position_is_clear: bool = true

	for cell_position_to_clear_for_player: Vector2i in all_cell_positions_to_clear_for_player:
		if (
			Globals.WorldMap.get_cell_data_at_map_local_position(cell_position_to_clear_for_player)
			!= Vector2i(-1, -1)
		):
			position_is_clear = false

	return position_is_clear


func player_joined(id: int, data: String) -> void:
	var player_uuid: String = ""
	if data != "":
		# Validate token and data within
		# NOTE: At this point an invalid token is merely wiped and rebuilt, as there is no "login",
		# We are only preventing people from hacking into another player's data.
		var json: JSON = JSON.new()
		var error: int = json.parse(data)
		if error != OK:
			printerr(
				"User data JSON Parse Error: ",
				json.get_error_message(),
				" in ",
				data,
				" at line ",
				json.get_error_line()
			)
		else:
			var player_data: Variant = json.data
			if typeof(player_data) != TYPE_DICTIONARY or not player_data.has("jwt"):
				printerr("Data error player data from ", id, ": ", player_data)
			else:
				var content: Dictionary = validate_and_decode_jwt(
					Globals.server_config["jwt_secret"], player_data["jwt"]
				)
				if content.has("uuid") and Globals.player_save_data.has(content["uuid"]):
					player_uuid = content["uuid"]
					Helpers.log_print(str("Player ", id, " uuid is ", player_uuid), "cyan")
				else:
					printerr("----------------------------------------------------")
					printerr("Player ", id, " joined with bad token content:")
					printerr(content)
					printerr("-----")
					printerr(Globals.player_save_data)
					printerr("----------------------------------------------------")
	if player_uuid == "":
		# If player has no valid UUID, they are new, so set them up with a unique UUID
		# that we can use to store data against.
		# Generate UUID for player
		player_uuid = uuid_util.v4()
		Globals.player_save_data[player_uuid] = {
			"uuid": player_uuid,
		}

	# Save player's UUID to peer list so we can find it later
	peers[id]["uuid"] = player_uuid

	# Spawn a character/player for the client
	var character: Node = player_character_template.instantiate()
	character.player = id  # Set player id.

	var potential_player_position: Vector2 = Vector2(0, 0)

	# Use saved player position if it exists
	if (
		Globals.player_save_data[player_uuid].has("position")
		and Globals.player_save_data[player_uuid]["position"].has("x")
		and Globals.player_save_data[player_uuid]["position"].has("y")
	):
		potential_player_position = Vector2(
			Globals.player_save_data[player_uuid]["position"]["x"],
			Globals.player_save_data[player_uuid]["position"]["y"],
		)

	var reached_bottom_of_map: bool = false
	var last_x_shift_direction: String = "positive"
	var last_x_shift_count: int = 0

	update_remote_pre_game_overlay_message.rpc_id(id, "Finding our place in the world...")
	var clear_and_safe_position_found: bool = false
	while not clear_and_safe_position_found:
		var potential_player_position_in_map_coordinates: Vector2i = (
			Globals.WorldMap.get_cell_position_at_global_position(potential_player_position)
		)

		if reached_bottom_of_map:
			# We must shift left/right and try again
			# This should provide a "back and forth" shifting left and right at greater and greater amounts
			# But not on the first round. The first time just try to use the same X position, hence start with 0,
			# and increment it after.
			if (
				last_x_shift_direction == "positive"
				and potential_player_position_in_map_coordinates.x > Globals.MapEdges.Min.x
			):
				last_x_shift_direction = "negative"
				potential_player_position_in_map_coordinates.x -= last_x_shift_count
			else:
				last_x_shift_direction = "positive"
				potential_player_position_in_map_coordinates.x += last_x_shift_count
			last_x_shift_count += 1

		reached_bottom_of_map = false  # reset

		var next_position_down_cell_contents: Vector2i = Vector2i(-1, -1)
		var descender_counter: int = 0
		while next_position_down_cell_contents == Vector2i(-1, -1) and not reached_bottom_of_map:
			next_position_down_cell_contents = Globals.WorldMap.get_cell_data_at_map_local_position(
				Vector2i(
					potential_player_position_in_map_coordinates.x,
					potential_player_position_in_map_coordinates.y + descender_counter
				)
			)
			reached_bottom_of_map = (
				potential_player_position_in_map_coordinates.y + descender_counter
				> Globals.MapEdges.Max.y
			)
			descender_counter += 1

		if not reached_bottom_of_map:
			potential_player_position = Globals.WorldMap.get_global_position_at_map_local_position(
				Vector2i(
					potential_player_position_in_map_coordinates.x,
					potential_player_position_in_map_coordinates.y + descender_counter - 1
				)
			)
			clear_and_safe_position_found = check_location_and_surroundings(
				potential_player_position
			)
			reached_bottom_of_map = true  # If we loop, always force a left/right shift at the next loop.
		else:
			# If we did, then set the position to be the same X position but at the highest Y point possible + player's size
			potential_player_position = Globals.WorldMap.get_global_position_at_map_local_position(
				Vector2i(potential_player_position_in_map_coordinates.x, Globals.MapEdges.Min.y - 4)
			)
		# Otherwise, do not update the potential_player_position and start over
		# TODO: There is nothing to stop this from looping forever in a worse case scenario

	# TODO: Use saved player rotation if it exists
	#if Globals.player_save_data[player_uuid].has("rotation"):
	# TODO: Reimplement this for a 2D character.
	#Helpers.log_print(str("Rotation: ", Globals.player_save_data[player_uuid]["rotation"]))
	# character.rotation = Vector3(
	# 	Globals.player_save_data[player_uuid]["rotation"]["x"],
	# 	Globals.player_save_data[player_uuid]["rotation"]["y"],
	# 	Globals.player_save_data[player_uuid]["rotation"]["z"]
	# )

	character.name = str(id)
	get_node("../Main/Players").add_child(character, true)
	character.set_multiplayer_authority(character.player)
	character.set_player_position.rpc_id(id, potential_player_position)
	Globals.Players[id] = character

	# Always update our saved data now in case this is a new player
	Helpers.save_server_player_save_data_to_file()

	# Always send player an updated token, so that their expiration date is updated
	var new_player_jwt: String = generate_jwt(Globals.server_config["jwt_secret"], player_uuid)
	var data_for_player: Dictionary = {"jwt": new_player_jwt}
	send_data_to(id, Message.PLAYER_TOKEN, JSON.stringify(data_for_player))

	# Clean up initial map data sending data in MapController to avoid memory leak
	# and possible corruption if another player joins later and gets the same multiplayer_id
	Globals.WorldMap.server_side_per_player_initial_map_data.erase(id)
