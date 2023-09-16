extends RigidBody3D

@export var bounds_distance: int = 100

@export var push_factor: float = 0.9

var player_focused: String
@export var player_holding_me: String


# Called when the node enters the scene tree for the first time.
func _ready():
	set_physics_process(Globals.is_server)
	if Globals.is_server:
		position = Vector3(8, 1, -8)
		rotation.y = -45.0


func _physics_process(_delta):
#	print(
#		"grabbing|",
#		Globals.local_debug_instance_number,
#		"|",
#		multiplayer.get_unique_id(),
#		"|",
#		name,
#		"|",
#		player_holding_me
#	)
	if player_holding_me != "":
		var players_parent: Node = get_tree().get_root().get_node("Main/Players")
		var player_to_follow: Node = players_parent.get_node_or_null(player_holding_me)
		if player_to_follow:
			var transform_hold_obj = player_to_follow.get_global_transform()
			var some_distance_between_you_and_object: int = 1
			transform_hold_obj.origin = (
				transform_hold_obj.origin
				- transform_hold_obj.basis.z * some_distance_between_you_and_object
			)
			#print(transform_hold_obj.origin)
			position = transform_hold_obj.origin
			rotation = player_to_follow.rotation
			#self.set_transform(transform_hold_obj)

#			var aim = player_to_follow.get_global_transform().basis
#			print(aim, aim.x, aim.y, aim.z)
#			position = Vector3(aim.x, aim.y, aim.z - 0.25)

	# Only the server should act on this object, as the server owns it,
	# especially the delete part.
	# Delete if it gets out of bounds
	if abs(position.x) > bounds_distance:
		get_parent().queue_free()
	if abs(position.y) > bounds_distance:
		get_parent().queue_free()
	if abs(position.z) > bounds_distance:
		get_parent().queue_free()


func select(other_name):
	if player_focused == "":
		player_focused = other_name
		print(other_name, " is near ", get_parent().name)
		$SpotLight3D.visible = true


func unselect(other_name):
	player_focused = ""
	print(other_name, " moved away from ", get_parent().name)
	$SpotLight3D.visible = false


func grab(other_name) -> void:
	if player_holding_me == "":
		player_holding_me = other_name
	print(
		"grabbed|",
		Globals.local_debug_instance_number,
		"|",
		multiplayer.get_unique_id(),
		"|",
		other_name,
		"|",
		name,
		"|",
		player_holding_me
	)


func my_name() -> String:
	return get_parent().name


func input_position(new_position):
	self.position = new_position
