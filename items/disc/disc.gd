extends RigidBody2D

@export var spawn_position: Vector2


func _ready() -> void:
	set_physics_process(get_multiplayer_authority() == multiplayer.get_unique_id())
	if Globals.is_server and spawn_position:
		position = spawn_position
		Helpers.log_print(str("Setting ball position to ", spawn_position))
