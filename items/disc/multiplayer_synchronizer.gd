# https://forum.godotengine.org/t/jittery-rigidbody-movement-on-client-side/38377/3
# TODO: This does NOT synchronize rotation at all. I'm not sure how you even get or set rotation on 2D objects.
class_name PhysicsSynchronizer
extends MultiplayerSynchronizer

enum {
	FRAME,
	ORIGIN,
	QUAT,  # the quaternion is used for an optimized rotation state
	LIN_VEL,
	ANG_VEL,
}

@export
var sync_bstate_array: Array = [0, Vector2.ZERO, Quaternion.IDENTITY, Vector2.ZERO, Vector2.ZERO]

var frame: int = 0
var last_frame: int = 0

@onready var sync_object: RigidBody2D = get_node(root_path)
@onready var body_state: PhysicsDirectBodyState2D = PhysicsServer2D.body_get_direct_state(
	sync_object.get_rid()
)


## Copy state to array
func get_state(state: PhysicsDirectBodyState2D, array: Array) -> void:
	array[ORIGIN] = state.transform.origin
	#array[QUAT] = state.transform.basis.get_rotation_quaternion()
	array[LIN_VEL] = state.linear_velocity
	array[ANG_VEL] = state.angular_velocity


## Copy array to state
func set_state(array: Array, state: PhysicsDirectBodyState2D) -> void:
	state.transform.origin = array[ORIGIN]
	#state.transform.basis = Basis(array[QUAT])
	state.linear_velocity = array[LIN_VEL]
	state.angular_velocity = array[ANG_VEL]


func get_physics_body_info() -> void:
	# server copy for sync
	get_state(body_state, sync_bstate_array)


func set_physics_body_info() -> void:
	# client rpc set from server
	set_state(sync_bstate_array, body_state)


func _physics_process(_delta: float) -> void:
	if is_multiplayer_authority() and sync_object.visible:
		frame += 1
		sync_bstate_array[FRAME] = frame
		get_physics_body_info()


# make sure to wire the "synchronized" signal to this function
func _on_synchronized() -> void:
	correct_error()
	# is this necessary?
	if is_previous_frame():
		return
	set_physics_body_info()


##  Very basic network jitter reduction
func correct_error() -> void:
	var diff: Vector2 = body_state.transform.origin - sync_bstate_array[ORIGIN]
#	print(name,": diff origin ", diff.length())
	# correct minor error, but snap to incoming state if too far from reality
	if diff.length() < 3.0:
		sync_bstate_array[ORIGIN] = body_state.transform.origin.lerp(
			sync_bstate_array[ORIGIN], 0.05
		)


func is_previous_frame() -> bool:
	if sync_bstate_array[FRAME] <= last_frame:
		return true
	last_frame = sync_bstate_array[FRAME]
	return false
