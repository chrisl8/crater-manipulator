extends CharacterBody3D
class_name MovementController

# Source: https://github.com/Whimfoome/godot-FirstPersonStarter

@export var gravity_multiplier: float = 3.0
@export var acceleration: int = 8
@export var deceleration: int = 10

@export_range(0.0, 1.0, 0.05) var air_control: float = 0.3
@export var jump_height: int = 10

# Get the gravity from the project settings to be synced with RigidDynamicBody nodes.
@onready
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * gravity_multiplier

# Set by the authority, synchronized on spawn.
@export var player: int = 1:
	set(id):
		player = id
		# Give authority over the player input to the appropriate peer.
		#$ServerSynchronizer.set_multiplayer_authority(id)
		$PlayerInput.set_multiplayer_authority(id)
		$Head.set_multiplayer_authority(id)

# Player synchronized input.
@onready var input = $PlayerInput

var previous_thing: float
var character_trimmed: bool = false



func _process(
	_delta: float,
) -> void:
	if (
		player > 1
		and not character_trimmed
		and $Head.get_multiplayer_authority() == multiplayer.get_unique_id()
	):
		character_trimmed = true
		$Character.get_node("Head").queue_free()
		$Character.get_node("Body").queue_free()
	rotation.y = input.camera_rotation_y


func _physics_process(delta: float) -> void:
	# if held_item_name != "":
	# 	var things_spawning_node = get_tree().get_root().get_node("Main/Things")
	# 	var existing_thing = things_spawning_node.get_node_or_null(held_item_name)
	# 	if existing_thing:
	# 		existing_thing.input_position(Vector3(8, 1, -8))
	#position = Vector3(8, 1, -8)

	if input.interacting:
		print(
			User.local_debug_instance_number, " ", name, " ", input.selected_thing_name, " Interact"
		)
		if input.selected_thing_name != "":
			var things_parent: Node = get_tree().get_root().get_node("Main/Things")
			var thing_to_grab: Node = things_parent.get_node_or_null(input.selected_thing_name)
			if thing_to_grab:
				print(thing_to_grab)
				var thing_to_grab_body: Node = thing_to_grab.get_node_or_null("./RigidBody3D")
				if thing_to_grab_body and thing_to_grab_body.has_method("grab"):
					print(thing_to_grab_body)
					thing_to_grab_body.grab(name)
	input.interacting = false

	if is_on_floor():
		if input.jumping:
			velocity.y = jump_height
	else:
		velocity.y -= gravity * delta
	# Reset jump state.
	input.jumping = false
	var direction: Vector3 = direction_input()
	accelerate(delta, direction)

	# Apply impulses to rigid bodies that we encounter to make them move.
	# https://kidscancode.org/godot_recipes/3.x/physics/kinematic_to_rigidbody/index.html
	# https://github.com/godotengine/godot/issues/74804
	# There are other ways, but that results in pushing these things
	# through walls, so this is the way.
	# NOTE: Do call this in the character/player's script BEFORE move_and_slide()
	# or else your velocity may be 0 at this moment (because you already bumped into the thing) and hence no
	# impulse will be telegraphed. If you call move_and_slide() first you will see that you run up to something
	# and just immediately stop and the object doesn't move.
	for index in range(get_slide_collision_count()):
		# We get one of the collisions with the player
		var collision: KinematicCollision3D = get_slide_collision(index)

		# if collision.get_collider().has_method("push"):
		# 	collision.get_collider().push(collision.get_normal(), velocity.length())

	move_and_slide()


func direction_input() -> Vector3:
	var direction: Vector3 = Vector3()
	var aim: Basis = get_global_transform().basis
	direction = aim.z * -input.input_axis.x + aim.x * input.input_axis.y
	return direction


func accelerate(delta: float, direction: Vector3) -> void:
	# Using only the horizontal velocity, interpolate towards the input.
	var temp_vel: Vector3 = velocity
	temp_vel.y = 0

	var temp_accel: float
	var target: Vector3 = direction * input.speed

	if direction.dot(temp_vel) > 0:
		temp_accel = acceleration
	else:
		temp_accel = deceleration

	if not is_on_floor():
		temp_accel *= air_control

	# https://github.com/Whimfoome/godot-FirstPersonStarter/issues/32
	var clamped_accel = clamp(temp_accel * delta, 0.0, 1.0)
	temp_vel = temp_vel.lerp(target, clamped_accel)
	#temp_vel = temp_vel.lerp(target, temp_accel * delta)

	velocity.x = temp_vel.x
	velocity.z = temp_vel.z


var held_item_name: String = ""


func _spawn_chair():
	if held_item_name == "":
		print("..")
		var thing_name_to_spawn: String = "Chair01a"
		var things_spawning_node: Node = get_tree().get_root().get_node("Main/Things")
		var existing_thing: Node = things_spawning_node.get_node_or_null(thing_name_to_spawn)
		var chair: Resource = preload("res://things/chair/chair.tscn")
		if not existing_thing:
			print("...")
			var new_thing = chair.instantiate()
			new_thing.name = str(thing_name_to_spawn)
			things_spawning_node.add_child(new_thing)
			print(thing_name_to_spawn)
