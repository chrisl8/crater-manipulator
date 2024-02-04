extends Node2D

@export var RotPoint: Node2D
@export var RotSpeed: float = 10.0

@export var LeftLeg: Node2D
@export var RightLeg: Node2D

var Lastposition

@export var Flipped: bool = false:
	set(new_value):
		Flipped = new_value
		LeftLeg.Flipped = Flipped
		RightLeg.Flipped = Flipped

func _ready():
	Lastposition = global_position
	pass

func _process(delta):
	var Distance = global_position.x - Lastposition.x
	var Move: bool = abs(Distance) > 0.0
	if(Move):
		RotPoint.rotate(Distance*delta*RotSpeed * (-1.0 if Flipped else 1.0))
	LeftLeg.Move = Move
	RightLeg.Move = Move
	Lastposition = global_position
	pass
