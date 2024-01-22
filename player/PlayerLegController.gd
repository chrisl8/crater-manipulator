extends Node2D

@export var IKController: Node2D
@export var IKTarget: Node2D

@export var UpperSegment: Node2D
#@export var LowerSegment: Node2D

var Length

@export var Foot: Node2D
@export var FootHeight: float = 1.0

@export var Move: bool = false

@export var IdleIKTarget: Node2D

var TimeSinceTargetFound: float = 0.0

@export var AirborneIKTarget: Node2D

@export var OtherLeg: Node2D
@export var Grounded: bool = true

func _ready():
	pass

const MaxAirborneTime: float = 0.7
func _process(delta):


	var CurrentIKTarget = IdleIKTarget.global_position
	if(Move):
		CurrentIKTarget = IKTarget.global_position

	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
			UpperSegment.global_position,CurrentIKTarget
		)
	query.exclude = [self]
	var result: Dictionary = space_state.intersect_ray(query)
	if result.size() > 0:
		TimeSinceTargetFound = 0.0
		var HitPoint: Vector2 = result["position"]
		IKController.Target = HitPoint - Vector2(0,FootHeight)
	else:
		TimeSinceTargetFound+=delta
		if(Grounded or OtherLeg.Grounded):
			IKController.Target = CurrentIKTarget - Vector2(0,FootHeight)
		else:
			IKController.Target = AirborneIKTarget.global_position - Vector2(0,FootHeight)

	Grounded = TimeSinceTargetFound < MaxAirborneTime
	Foot.global_rotation = 0
	pass
