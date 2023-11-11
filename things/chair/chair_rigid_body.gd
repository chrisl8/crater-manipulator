extends RigidBody3D

@export var bounds_distance: int = 100

@export var push_factor: float = 0.9

var player_focused: String


func _ready() -> void:
	set_physics_process(get_multiplayer_authority() == multiplayer.get_unique_id())

	# TODO: Figure out a way to use this without having the location hard coded ahead of time.
	if Globals.is_server:
		position = Vector3(8, 1, -8)
		rotation.y = -45.0


func _physics_process(_delta: float) -> void:
	# Delete if it gets out of bounds
	# Whatever spawned it should track and respawn it if required
	if abs(position.x) > bounds_distance:
		get_parent().queue_free()
	if abs(position.y) > bounds_distance:
		get_parent().queue_free()
	if abs(position.z) > bounds_distance:
		get_parent().queue_free()


func select(other_name: String) -> void:
	if player_focused == "":
		player_focused = other_name
		Helpers.log_print(str(other_name, " is near ", get_parent().name), "saddlebrown")
		$SpotLight3D.visible = true


func unselect(other_name: String) -> void:
	player_focused = ""
	Helpers.log_print(str(other_name, " moved away from ", get_parent().name), "saddlebrown")
	$SpotLight3D.visible = false


@rpc("any_peer", "call_remote") func grab() -> void:
	Helpers.log_print("Deleting myself now", "saddlebrown")
	# Just delete myself if someone grabbed me
	get_node(".").queue_free()


func my_name() -> String:
	return get_parent().name


func input_position(new_position: Vector3) -> void:
	self.position = new_position
