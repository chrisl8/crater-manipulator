extends Node2D

@export var UpperSegment: Node2D
@export var LowerSegment: Node2D

@export var Target: Vector2

@export var FlipDirection: bool

var Length


func _ready():
	Length = UpperSegment.global_position.distance_to(LowerSegment.global_position)


func _process(_delta):
	if FlipDirection:
		#print(Target)
		#UpperSegment.global_position = Target
		#print(LowerSegment.global_position)
		pass
	var Distance = Target.distance_to(UpperSegment.global_position)
	var Height = 0.0
	if Distance < Length * 2.0:
		Height = sqrt(Length * Length - Distance * Distance / 4.0)
	UpperSegment.look_at(Target)
	var MidPoint = (UpperSegment.global_position + Target) / 2.0
	var UpperIKTarget
	if FlipDirection:
		UpperIKTarget = MidPoint - UpperSegment.global_transform.y * Height
	else:
		UpperIKTarget = MidPoint + UpperSegment.global_transform.y * Height
	UpperSegment.look_at(UpperIKTarget)
	LowerSegment.look_at(Target)
