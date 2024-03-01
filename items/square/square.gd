extends RigidBody2D

@export var spawn_position: Vector2


func _ready() -> void:
	set_physics_process(is_multiplayer_authority())
	if Globals.is_server and spawn_position:
		position = spawn_position
		Helpers.log_print(str("Setting box position to ", spawn_position))


func nearby(is_nearby: bool, _body: Node2D) -> void:
	if is_nearby:
		$HighlightMesh.visible = true
	else:
		$HighlightMesh.visible = false


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
		player.spawn_player_controlled_thing.rpc(name)