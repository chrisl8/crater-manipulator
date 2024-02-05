extends Node2D

@export var UpperSegment: Node2D
@export var LowerSegment: Node2D

@export var Target: Vector2

@export var FlipDirection: bool

var Length: float


func _ready() -> void:
	Length = UpperSegment.global_position.distance_to(LowerSegment.global_position)


func _process(_delta: float) -> void:
	if FlipDirection:
		#print(Target)
		#UpperSegment.global_position = Target
		#print(LowerSegment.global_position)
		pass
	var Distance: float = Target.distance_to(UpperSegment.global_position)
	var Height: float = 0.0
	if Distance < Length * 2.0:
		Height = sqrt(Length * Length - Distance * Distance / 4.0)
	UpperSegment.look_at(Target)
	var MidPoint: Vector2 = (UpperSegment.global_position + Target) / 2.0
	var UpperIKTarget: Vector2
	if FlipDirection:
		UpperIKTarget = MidPoint - UpperSegment.global_transform.y * Height
	else:
		UpperIKTarget = MidPoint + UpperSegment.global_transform.y * Height
	UpperSegment.look_at(UpperIKTarget)
	LowerSegment.look_at(Target)
