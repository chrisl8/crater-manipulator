extends Node2D

@export var upper_segment: Node2D
@export var lower_segment: Node2D

@export var target: Vector2

@export var flip_direction: bool

var length: float


func _ready() -> void:
	length = upper_segment.global_position.distance_to(lower_segment.global_position)


func _process(_delta: float) -> void:
	if flip_direction:
		#print(target)
		#upper_segment.global_position = target
		#print(lower_segment.global_position)
		pass
	var distance: float = target.distance_to(upper_segment.global_position)
	var height: float = 0.0
	if distance < length * 2.0:
		height = sqrt(length * length - distance * distance / 4.0)
	upper_segment.look_at(target)
	var mid_point: Vector2 = (upper_segment.global_position + target) / 2.0
	var upper_ik_target: Vector2
	if flip_direction:
		upper_ik_target = mid_point - upper_segment.global_transform.y * height
	else:
		upper_ik_target = mid_point + upper_segment.global_transform.y * height
	upper_segment.look_at(upper_ik_target)
	lower_segment.look_at(target)
