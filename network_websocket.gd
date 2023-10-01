extends Node

var ws: WebSocketPeer = WebSocketPeer.new()

signal reset
signal close_popup

var ready_to_connect: bool = false
var peers: Dictionary
var peer_count: int = -1
var peers_have_connected: bool = false
var network_initialized: bool = false
var game_scene_initialize_in_progress: bool = false
var game_scene_initialized: bool = false
var network_connection_initiated: bool = false

var player_character_template: PackedScene = preload("res://player/player.tscn")
var level_scene: PackedScene = preload("res://spaceship/spaceship.tscn")
# A big open area for testing stuff.
#var level_scene: PackedScene = preload("res://character_test_level/character_test.tscn")

var websocket_multiplayer_peer: WebSocketMultiplayerPeer

@export var player_spawn_point: Vector3 = Vector3(4, 1, -4)


func _process(_delta) -> void:
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
		Helpers.log_print(str("New peer count is: ", peer_count))

	if not Globals.is_server:
		# Only server proceeds past this point,
		# adding and removing objects, etc.
		return

	# In Debug mode, exit server if everyone disconnects in order to speed up debugging sessions (less windows to close)
	if OS.is_debug_build() and peers_have_connected and peer_count < 1:
		Helpers.log_print(
			"Closing server due to all clients disconnecting and this running in Debug mode."
		)
		get_tree().quit()  # Quits the game

	# Initialize the Level if it isn't yet
	if not game_scene_initialized:
		if not game_scene_initialize_in_progress:
			# Helpers.log_print("Load level")
			game_scene_initialize_in_progress = true
			load_level.call_deferred(level_scene)
		elif get_node_or_null("../Main/Level/game_scene"):
			game_scene_initialized = true
		return

	Spawner.things()


func _ready():
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected_to_server)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)


func load_level(scene: PackedScene):
	# Helpers.log_print("Loading Scene")
	var level_parent: Node = get_tree().get_root().get_node("Main/Level")
	for c in level_parent.get_children():
		level_parent.remove_child(c)
		c.queue_free()
	var game_scene = scene.instantiate()
	game_scene.name = "game_scene"
	level_parent.add_child(game_scene)


func generate_jwt(secret: String, player_uuid: String) -> String:
	var jwt_algorithm: JWTAlgorithm = JWTAlgorithmBuilder.HS256(secret)
	var jwt_builder: JWTBuilder = (
		JWT
		. create()
		. with_expires_at(
			Time.get_unix_time_from_datetime_dict(Time.get_date_dict_from_system()) + 60 * 24 * 365
		)
		. with_issuer("Space Game")
		. with_payload({"uuid": player_uuid})
	)
	var jwt: String = jwt_builder.sign(jwt_algorithm)
	return jwt


func validate_and_decode_jwt(secret: String, jwt: String) -> Dictionary:
	var content: Dictionary = {}
	var jwt_algorithm: JWTAlgorithm = JWTAlgorithmBuilder.HS256(secret)
	var jwt_verifier: JWTVerifier = JWT.require(jwt_algorithm).build()  # Reusable Verifier
	if jwt_verifier.verify(jwt) == JWTVerifier.JWTExceptions.OK:
		var jwt_decoder: JWTDecoder = JWT.decode(jwt)
		content = jwt_decoder.get_claims()
	else:
		print(jwt_verifier.exception)
	return content


func _peer_connected(id):
	Helpers.log_print(str("Peer ", id, " connected."))
	peers[id] = {}


func _peer_disconnected(id) -> void:
	Helpers.log_print(str("Peer ", id, " Disconnected."))
	var player_uuid: String = ""
	if peers.has(id):
		if peers[id].has("uuid"):
			player_uuid = peers[id]["uuid"]
		peers.erase(id)
	if not Globals.is_server:
		return
	# TODO: Save player's position so we can use it if they join again.

	var player_spawner_node: Node = get_node_or_null("../Main/Players")
	if player_spawner_node and player_spawner_node.has_node(str(id)):
		var player: Node = player_spawner_node.get_node(str(id))
		Helpers.log_print(
			str(
				"Player ",
				id,
				" disconnected while at position ",
				player.position,
				" rotation ",
				player.rotation
			)
		)
		if player_uuid != "":
			Globals.player_save_data[player_uuid]["position"] = {
				"x": player.position.x, "y": player.position.y, "z": player.position.z
			}
			Globals.player_save_data[player_uuid]["rotation"] = {
				"x": player.rotation.x, "y": player.rotation.y, "z": player.rotation.z
			}
			Helpers.save_server_player_save_data_to_file()
		player.queue_free()


func player_save_data_filename() -> String:
	var file_name: String = "user://save_game.dat"
	if Globals.local_debug_instance_number > -1:
		file_name = str("user://save_game_", Globals.local_debug_instance_number, ".dat")
	return file_name


func _connected_to_server():
	Helpers.log_print("I connected to the server!")
	close_popup.emit()

	#TODO: Testing data read/write
	#save_player_data("doot!")
	var saved_player_data: String = Helpers.load_data_from_file(player_save_data_filename())

	# Server does not spawn our player until we send a "join" message
	send_data_to(1, Message.PLAYER_JOINED, saved_player_data)


func _connection_failed():
	Helpers.log_print("My connection failed. =(")
	reset_connection()


func _server_disconnected():
	Helpers.log_print("Server Disconnected")
	reset_connection()


func reset_connection():
	Helpers.log_print("Reset Connection")
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
	reset.emit(5)


func init_network():
	Helpers.log_print("Init Network")
	websocket_multiplayer_peer = WebSocketMultiplayerPeer.new()
	# This is a client/server setup, NOT a Mesh.
	if Globals.is_server:
		websocket_multiplayer_peer.create_server(9090)
	else:
		var error: int = websocket_multiplayer_peer.create_client(Globals.url)  # WebSocket
		if error:
			Helpers.log_print(error)
	get_tree().get_multiplayer().multiplayer_peer = websocket_multiplayer_peer
	close_popup.emit()
	network_initialized = true


func send_data_to(id: int, msg_type: Message, data: String):
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


enum Message { PLAYER_JOINED, PLAYER_TOKEN }

@rpc("any_peer") func data_received(data) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()

	var json: JSON = JSON.new()
	var error = json.parse(data)
	if error != OK:
		print(
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
		print("Data error in: ", parsed_message, " from ", sender_id)
		return

	if parsed_message.type == Message.PLAYER_JOINED:
		player_joined(sender_id, parsed_message.data)
		return

	if parsed_message.type == Message.PLAYER_TOKEN:
		Helpers.save_data_to_file(player_save_data_filename(), parsed_message.data)
		return

	print("Unknown Message Type in: ", parsed_message, " from ", sender_id)


var uuid_util: Resource = preload("res://addons/godot-uuid/uuid.gd")


func player_joined(id: int, data: String):
	if Globals.is_server and id > 1:  # I'm not sure this check is necessary
		var player_uuid: String = ""
		if data != "":
			# Validate token and data within
			# NOTE: At this point an invalid token is merely wiped and rebuilt, as there is no "login",
			# We are only preventing people from hacking into another player's data.
			var json: JSON = JSON.new()
			var error = json.parse(data)
			if error != OK:
				print(
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
					print("Data error player data from ", id, ": ", player_data)
				else:
					var content: Dictionary = validate_and_decode_jwt(
						Globals.server_config["jwt_secret"], player_data["jwt"]
					)
					if content.has("uuid") and Globals.player_save_data.has(content["uuid"]):
						player_uuid = content["uuid"]
						Helpers.log_print(str("Player ", id, " uuid is ", player_uuid))
					else:
						print("----------------------------------------------------")
						print("Player ", id, " joined with bad token content:")
						print(content)
						print("-----")
						print(Globals.player_save_data)
						print("----------------------------------------------------")
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

		var character = player_character_template.instantiate()
		character.player = id  # Set player id.

		# Use saved player position or randomize it around the spawn area
		if (
			Globals.player_save_data[player_uuid].has("position")
			and Globals.player_save_data[player_uuid]["position"].has("x")
			and Globals.player_save_data[player_uuid]["position"].has("y")
			and Globals.player_save_data[player_uuid]["position"].has("z")
		):
			character.position = Vector3(
				Globals.player_save_data[player_uuid]["position"]["x"],
				Globals.player_save_data[player_uuid]["position"]["y"],
				Globals.player_save_data[player_uuid]["position"]["z"]
			)
		else:
			# Randomize character position.
			var pos: Vector2 = Vector2.from_angle(randf() * 2 * PI)
			const SPAWN_RANDOM: float = 2.0
			character.position = Vector3(
				player_spawn_point.x + (pos.x * SPAWN_RANDOM * randf()),
				player_spawn_point.y,
				player_spawn_point.z + (pos.y * SPAWN_RANDOM * randf())
			)

		# Use saved player rotation if it exists
		if (
			Globals.player_save_data[player_uuid].has("rotation")
			and Globals.player_save_data[player_uuid]["rotation"].has("x")
			and Globals.player_save_data[player_uuid]["rotation"].has("y")
			and Globals.player_save_data[player_uuid]["rotation"].has("z")
		):
			character.rotation = Vector3(
				Globals.player_save_data[player_uuid]["rotation"]["x"],
				Globals.player_save_data[player_uuid]["rotation"]["y"],
				Globals.player_save_data[player_uuid]["rotation"]["z"]
			)
		character.name = str(id)
		get_node("../Main/Players").add_child(character, true)
		character.set_multiplayer_authority(character.player)

		# Always update our saved data now in case this is a new player
		Helpers.save_server_player_save_data_to_file()

		# Always send player an updated token, so that their expiration date is updated
		var new_player_jwt: String = generate_jwt(Globals.server_config["jwt_secret"], player_uuid)
		var data_for_player: Dictionary = {"jwt": new_player_jwt}
		send_data_to(id, Message.PLAYER_TOKEN, JSON.stringify(data_for_player))