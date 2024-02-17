extends Node2D

@export var rot_point: Node2D
@export var rot_speed: float = 10.0
@export var left_leg: Node2D
@export var right_leg: Node2D

@export var flipped: bool = false:
	set(new_value):
		flipped = new_value
		left_leg.flipped = flipped
		right_leg.flipped = flipped

var last_position: Vector2


func _ready() -> void:
	last_position = global_position


func _process(delta: float) -> void:
	var distance: float = global_position.x - last_position.x
	var move: bool = abs(distance) > 0.000001
	if move:
		rot_point.rotate(distance * rot_speed * (-1.0 if flipped else 1.0))
	left_leg.move = move
	right_leg.move = move
	last_position = global_position
