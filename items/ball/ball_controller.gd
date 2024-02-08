extends RigidBody2D

@export var bounds_distance: int = 11000
@export var push_factor: float = 0.9
@export var spawn_position: Vector2

var player_focused: String


func _ready() -> void:
	set_physics_process(get_multiplayer_authority() == multiplayer.get_unique_id())
	if Globals.is_server and spawn_position:
		position = spawn_position
		Helpers.log_print(str("Setting ball position to ", spawn_position))
		# Only position, not rotation is currently passed in by the spawner
		rotation = -45.0


func _physics_process(_delta: float) -> void:
	# Delete if it gets out of bounds
	# Whatever spawned it should track and respawn it if required
	if position.x < Globals.MapEdges.Min.x or position.x > Globals.MapEdges.Max.x:
		queue_free()
	if position.y < Globals.MapEdges.Min.y or position.y > Globals.MapEdges.Max.y:
		queue_free()


func select(other_name: String) -> void:
	if player_focused == "":
		player_focused = other_name
		Helpers.log_print(str(other_name, " is near me (", name, ")"), "saddlebrown")
		$SpotLight3D.visible = true


func unselect(other_name: String) -> void:
	player_focused = ""
	Helpers.log_print(str(other_name, " moved away from me (", name, ")"), "saddlebrown")
	$SpotLight3D.visible = false


func my_name() -> String:
	return get_parent().name


func input_position(new_position: Vector2) -> void:
	self.position = new_position
