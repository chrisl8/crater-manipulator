extends RigidBody2D

@export var spawn_position: Vector2


func _ready() -> void:
	set_physics_process(is_multiplayer_authority())
	if Globals.is_server and spawn_position:
		position = spawn_position
		Helpers.log_print(str("Setting ball position to ", spawn_position))


func nearby(is_nearby: bool, _body: Node2D) -> void:
	if is_nearby:
		$HighlightMesh.visible = true
	else:
		$HighlightMesh.visible = false
