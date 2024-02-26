extends RigidBody2D

@export var player: int = -1
@export var player_spawn_point: Vector2 = Vector2(4, 1.5)
@export var synced_position: Vector2 = Vector2(0, 0):
	set(new_value):
		synced_position = new_value
		update_synced_position = !player == multiplayer.get_unique_id()
@export var synced_rotation: float = 0:
	set(new_value):
		synced_rotation = new_value
		update_synced_rotation = !player == multiplayer.get_unique_id()
@export var camera: Node
@export var interaction_controller: Node2D
@export var inventory_manager: Node2D
@export var player_canvas: CanvasLayer

var update_synced_position: bool = false
var update_synced_rotation: bool = false


func _ready() -> void:
	# Attempt to fix character getting stuck on tiles as they move parallel to them
	# https://github.com/godotengine/godot/issues/47148
	# https://github.com/godotengine/godot/issues/50595#issuecomment-882647580
	# See here for documentation on this setting:
	# https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-physics-2d-solver-contact-max-allowed-penetration
	# "In this example, it will be set to 0 but you can set any other value."
	# I believe the default is 0.3, so anything from 0.0 to < 0.3 should help improve this situation
	# Feel free two tweak the number as you see fit.
	var space: RID = get_world_2d().space
	PhysicsServer2D.space_set_param(
		space, PhysicsServer2D.SPACE_PARAM_CONTACT_MAX_ALLOWED_PENETRATION, 0.0
	)

	interaction_controller.initialize(player == multiplayer.get_unique_id())
	inventory_manager.initialize(player == multiplayer.get_unique_id())

	set_process(player == multiplayer.get_unique_id())
	set_physics_process(player == multiplayer.get_unique_id())
	set_process_input(player == multiplayer.get_unique_id())

	if player == multiplayer.get_unique_id():
		camera.make_current()
	else:
		camera.queue_free()
		gravity_scale = 0.0

	player_canvas.visible = !Globals.is_server


## Remotely force the player to a given position
@rpc("any_peer", "call_remote", "reliable")
func set_player_position(new_position: Vector2) -> void:
	Helpers.log_print(str("Player was forced to ", new_position), "red")
	global_position = new_position


func _physics_process(delta: float) -> void:
	### Movement
	var move_input: Vector2 = relative_input()
	var speed: float = 200.0

	var velocity: Vector2 = linear_velocity
	if abs(move_input.x) > 0.1:
		velocity = Vector2(move_input.x * speed, velocity.y)
	else:
		var damp: float = 5000.0
		var dampening: float = velocity.x
		if velocity.x < 0.0:
			dampening = velocity.x - (damp * delta) * (velocity.x / abs(velocity.x))
			dampening = clamp(dampening, velocity.x, 0.0)
		elif velocity.x > 0:
			dampening = velocity.x - (damp * delta) * (velocity.x / abs(velocity.x))
			dampening = clamp(dampening, 0.0, velocity.x)

		velocity = Vector2(dampening, velocity.y)
	if abs(move_input.y) > 0.1:
		velocity = Vector2(velocity.x, move_input.y * speed)

	linear_velocity = velocity
	synced_position = position
	synced_rotation = rotation


# Get movement vector based on input, relative to the player's head transform
func relative_input() -> Vector2:
	# initialize the movement vector
	var move: Vector2 = Vector2()
	# Get cumulative input on axes
	var input: Vector3 = Vector3()
	input.z += int(Input.is_action_pressed("move_forward"))
	input.z -= int(Input.is_action_pressed("move_backward"))
	input.x += int(Input.is_action_pressed("move_right"))
	input.x -= int(Input.is_action_pressed("move_left"))
	# Add input vectors to movement relative to the direction the head is facing
	move.x = input.x
	move.y = -input.z
	# Normalize to prevent stronger diagonal forces
	return move.normalized()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if !player == multiplayer.get_unique_id():
		if update_synced_position and update_synced_rotation:
			state.transform = Transform2D(synced_rotation, synced_position)
		elif update_synced_position:
			state.transform = Transform2D(state.transform.get_rotation(), synced_position)
		elif update_synced_rotation:
			state.transform = Transform2D(synced_rotation, state.origin)
		update_synced_position = false
		update_synced_rotation = false


@rpc("any_peer", "call_remote", "reliable")
func add_inventory_data(data: Dictionary) -> void:
	if player == multiplayer.get_unique_id():
		inventory_manager.add_data(data)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"craft"):
		Globals.player_has_done.press_craft_button = true
		# Always Start with a ball
		var player_node: Node = get_node_or_null(
			str("/root/Main/Players/", player, "/Interaction Controller")
		)
		if player_node and player_node.has_method("spawn_player_controlled_thing"):
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			var id: int = rng.randi()
			var thing_name_to_spawn: String = str("Ball", "-", id)
			player_node.spawn_player_controlled_thing.rpc(thing_name_to_spawn, "Placing")
	elif event.is_action_released(&"craft"):
		var player_node: Node = get_node_or_null(
			str("/root/Main/Players/", player, "/Interaction Controller")
		)
		if player_node and player_node.has_method("spawn_player_controlled_thing"):
			player_node.de_spawn_placing_item.rpc()


func _on_personal_space_body_entered(body: Node2D) -> void:
	if is_multiplayer_authority() and body.has_method("nearby"):
		if is_multiplayer_authority():
			body.nearby(true, body)


func _on_personal_space_body_exited(body: Node2D) -> void:
	if is_multiplayer_authority() and body.has_method("nearby"):
		body.nearby(false, body)
