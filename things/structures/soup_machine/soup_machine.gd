extends StaticBody2dStructure


func _ready() -> void:
	item_type = Globals.ItemTypes.STRUCTURE
	snaps = true
	width_in_tiles = 4
	height_in_tiles = 4
	set_physics_process(is_multiplayer_authority())
	if Globals.is_server and spawn_position:
		position = spawn_position
		Helpers.log_print(str("Setting Soup Machine position to ", spawn_position))


func _physics_process(_delta: float) -> void:
	# Only the server should act on this object, as the server owns it,
	# especially the delete part.
	# Delete if it gets out of bounds
	if (
		(
			abs(position.x)
			> (Globals.world_map.max_radius_in_tiles * Globals.world_map.single_tile_width)
		)
		or (
			abs(position.y)
			> (Globals.world_map.max_radius_in_tiles * Globals.world_map.single_tile_width)
		)
	):
		queue_free()


func nearby(is_nearby: bool, _body: Node2D) -> void:
	if is_nearby:
		$MeshInstance2D.modulate = Color(1.0, 216 / 255.0, 0.0, 1.0)
	else:
		$MeshInstance2D.modulate = Color(1.0, 1.0, 1.0, 1.0)


@rpc("any_peer", "call_local")
func grab() -> void:
	Helpers.log_print(
		str(
			"I (",
			name,
			") was grabbed by ",
			multiplayer.get_remote_sender_id(),
			" Deleting myself now"
		),
		"saddlebrown"
	)
	# Delete myself if someone grabbed me
	queue_free()
	# Once that is done, tell the player node that grabbed me to spawn a "held" version
	var player: Node = get_node_or_null(
		str("/root/Main/Players/", multiplayer.get_remote_sender_id(), "/Interaction Controller")
	)
	if player and player.has_method("spawn_player_controlled_thing"):
		player.spawn_player_controlled_thing.rpc(global_position, global_rotation, name)
