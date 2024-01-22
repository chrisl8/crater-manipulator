extends Node2D

@export var RotPoint: Node2D

var Lastposition

func _ready():
	Lastposition = global_position
	pass

func _process(delta):
	var Distance = global_position.distance_to(Lastposition)
	if(Distance > 1.0):
		RotPoint.rotate(Distance*delta)
	pass
