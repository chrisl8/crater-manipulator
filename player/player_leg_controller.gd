extends Node2D

const MAX_AIRBORNE_TIME: float = 0.7

@export var ik_controller: Node2D
@export var ik_target: Node2D
@export var upper_segment: Node2D
@export var foot: Node2D
@export var foot_height: float = 1.0
@export var move: bool = false
@export var idle_ik_target: Node2D
@export var airborne_ik_target: Node2D
@export var other_leg: Node2D
@export var grounded: bool = true
@export var flipped: bool = false

var time_since_target_found: float = 0.0


func _process(delta: float) -> void:
	var current_ik_target: Vector2 = idle_ik_target.global_position
	if move:
		current_ik_target = ik_target.global_position

	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		upper_segment.global_position, current_ik_target
	)
	query.exclude = [self]
	var result: Dictionary = space_state.intersect_ray(query)
	if result.size() > 0:
		time_since_target_found = 0.0
		var hit_point: Vector2 = result["position"]
		ik_controller.target = hit_point - Vector2(0, foot_height)
	else:
		time_since_target_found += delta
		if grounded or other_leg.grounded:
			ik_controller.target = current_ik_target - Vector2(0, foot_height)
		else:
			ik_controller.target = airborne_ik_target.global_position - Vector2(0, foot_height)

	grounded = time_since_target_found < MAX_AIRBORNE_TIME
	if !flipped:
		foot.global_rotation = 0.0
	else:
		foot.global_rotation = PI
