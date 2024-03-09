extends Line2D

@export var flipped: bool = false

#Should be exposed in future for general purpose use
var points_count: int = -1
var starting_x: Array = []
var last_position: Vector2
var displacement_intensity: float = 0.003
var damping_intensity: int = 10
var max_velocity: int = 40


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for point: Vector2 in points:
		starting_x.append(point.x)
	points_count = points.size()
	last_position = global_position


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var new_velocity: float = clampf(
		(global_position.x - last_position.x) / delta, -max_velocity, max_velocity
	)

	#print(Velocity * displacement_intensity)

	var point_index: int = 1
	while point_index < points_count:
		var offset: float = (
			-new_velocity
			* displacement_intensity
			* float(point_index)
			* float(point_index)
			* (-1.0 if flipped else 1.0)
		)
		points[point_index].x += offset
		points[point_index].x = lerpf(
			points[point_index].x, starting_x[point_index], damping_intensity * delta
		)
		point_index += 1

	last_position = global_position
