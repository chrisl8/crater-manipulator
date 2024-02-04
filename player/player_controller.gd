extends RigidBody2D

@export var player: int = -1
@export var player_spawn_point: Vector2 = Vector2(4, 1.5)

@export var SyncedPosition: Vector2 = Vector2(0, 0):
	set(new_value):
		SyncedPosition = new_value
		UpdateSyncedPosition = !IsLocal
var UpdateSyncedPosition: bool = false

@export var SyncedRotation: float = 0:
	set(new_value):
		SyncedRotation = new_value
		UpdateSyncedRotation = !IsLocal
var UpdateSyncedRotation: bool = false

@export var camera: Node

@export var InteractionController: Node2D

var IsLocal: bool = false


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

	IsLocal = player == multiplayer.get_unique_id()

	InteractionController.Initialize(IsLocal)
	InventoryManager.Initialize(IsLocal)

	set_process(IsLocal)
	set_physics_process(IsLocal)
	set_process_input(IsLocal)

	if IsLocal:
		camera.make_current()
		Globals.my_camera = camera
	else:
		camera.queue_free()
		gravity_scale = 0.0


func _process(_delta: float) -> void:
	if (
		get_multiplayer_authority() == multiplayer.get_unique_id()
		and Input.is_action_just_pressed(&"interact")
	):
		return


## Remotely force the player to a given position
@rpc("any_peer", "call_remote", "reliable")
func set_player_position(new_position: Vector2) -> void:
	Helpers.log_print(str("Player was forced to ", new_position), "red")
	position = new_position


func _physics_process(delta: float) -> void:
	'''
	if Input.is_action_pressed("sprint"):
		print("SPRINTING")
	elif Input.is_action_pressed("tiptoe"):
		print("TIPTOEING")
	else:
		print("WALKING")
	'''

	### Movement
	var MoveInput: Vector2 = relative_input()
	var Speed: float = 200.0

	var Velocity: Vector2 = linear_velocity
	if abs(MoveInput.x) > 0.1:
		Velocity = Vector2(MoveInput.x * Speed, Velocity.y)
	else:
		var Damp: float = 5000.0
		var Dampening: float = Velocity.x
		if Velocity.x < 0.0:
			Dampening = Velocity.x - (Damp * delta) * (Velocity.x / abs(Velocity.x))
			Dampening = clamp(Dampening, Velocity.x, 0.0)
		elif Velocity.x > 0:
			Dampening = Velocity.x - (Damp * delta) * (Velocity.x / abs(Velocity.x))
			Dampening = clamp(Dampening, 0.0, Velocity.x)

		Velocity = Vector2(Dampening, Velocity.y)
	if abs(MoveInput.y) > 0.1:
		Velocity = Vector2(Velocity.x, MoveInput.y * Speed)

	linear_velocity = Velocity
	SyncedPosition = position
	SyncedRotation = rotation


# Get movement vector based on input, relative to the player's head transform
func relative_input() -> Vector2:
	# Initialize the movement vector
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
	if !IsLocal:
		if UpdateSyncedPosition and UpdateSyncedRotation:
			state.transform = Transform2D(SyncedRotation, SyncedPosition)
		elif UpdateSyncedPosition:
			state.transform = Transform2D(state.transform.get_rotation(), SyncedPosition)
		elif UpdateSyncedRotation:
			state.transform = Transform2D(SyncedRotation, state.origin)
		UpdateSyncedPosition = false
		UpdateSyncedRotation = false


@export var InventoryManager: Node2D

@rpc("any_peer", "call_remote", "reliable")
func AddInventoryData(Data: Dictionary) -> void:
	if IsLocal:
		InventoryManager.AddData(Data)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ball"):
		Helpers.log_print("BALL!")
		Spawner.thing.rpc_id(1, "Ball", Vector2(position.x, position.y - 100))
