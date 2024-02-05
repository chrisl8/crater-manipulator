extends Node2D

@export var RotPoint: Node2D
@export var RotSpeed: float = 10.0

@export var LeftLeg: Node2D
@export var RightLeg: Node2D

var Lastposition: Vector2

@export var Flipped: bool = false:
	set(new_value):
		Flipped = new_value
		LeftLeg.Flipped = Flipped
		RightLeg.Flipped = Flipped


func _ready() -> void:
	Lastposition = global_position


func _process(delta: float) -> void:
	var Distance: float = global_position.x - Lastposition.x
	var Move: bool = abs(Distance) > 0.0
	if Move:
		RotPoint.rotate(Distance * delta * RotSpeed * (-1.0 if Flipped else 1.0))
	LeftLeg.Move = Move
	RightLeg.Move = Move
	Lastposition = global_position
