extends Line2D

#Shoudl be exposed in future for general purpose use
var PointsCount = -1
var StartingX = []
var LastPosition
var DisplacementIntensity = 0.003
var DampingIntensity = 10
var MaxVelocity = 40

@export var flipped: bool = false


# Called when the node enters the scene tree for the first time.
func _ready():
	for Point in points:
		StartingX.append(Point.x)
	PointsCount = points.size()
	LastPosition = global_position


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var Velocity = clampf((global_position.x - LastPosition.x) / delta, -MaxVelocity, MaxVelocity)

	#print(Velocity * DisplacementIntensity)

	var NewPointData = []
	var Index = 1
	while Index < PointsCount:
		var Offset = (
			-Velocity
			* DisplacementIntensity
			* float(Index)
			* float(Index)
			* (-1.0 if flipped else 1.0)
		)
		points[Index].x += Offset
		points[Index].x = lerpf(points[Index].x, StartingX[Index], DampingIntensity * delta)
		Index += 1

	LastPosition = global_position
