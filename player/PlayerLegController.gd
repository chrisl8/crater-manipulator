extends Node2D

@export var IKController: Node2D
@export var IKTarget: Node2D

@export var UpperSegment: Node2D
@export var LowerSegment: Node2D

var Length

func _ready():
	Length = UpperSegment.global_position.distance_to(LowerSegment.global_position)
	pass

func _process(delta):


	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
			UpperSegment.global_position,((IKTarget.global_position - UpperSegment.global_position)
		))
	query.exclude = [self]
	var result: Dictionary = space_state.intersect_ray(query)
	if result.size() > 0:
		var HitPoint: Vector2 = result["position"]
		IKController.Target = HitPoint
	else:
		IKController.Target = IKTarget.global_position


	
	pass
