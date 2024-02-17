extends Node2D

const MOVEMENT_SPEED: float = 16.0
var mouse_left_down: bool = false

var server_camera: Node


func _ready() -> void:
	server_camera = get_node("Camera2D")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	var move: Vector2 = Vector2()

	var input: Vector3 = Vector3()
	input.z += int(Input.is_action_pressed("move_forward"))
	input.z -= int(Input.is_action_pressed("move_backward"))
	input.x += int(Input.is_action_pressed("move_right"))
	input.x -= int(Input.is_action_pressed("move_left"))

	move.x = input.x
	move.y = -input.z

	global_position += move * MOVEMENT_SPEED


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == 1 and event.is_pressed():
			mouse_left_down = true
		elif event.button_index == 1 and not event.is_pressed():
			mouse_left_down = false
		elif event.button_index == 4 and event.pressed:
			# Zoom In
			var new_zoom_level_x: float = server_camera.zoom.x + 0.1 * server_camera.zoom.x
			# if new_zoom_level_x > -0.01:
			# 	new_zoom_level_x = -0.01
			var new_zoom_level_y: float = server_camera.zoom.y + 0.1 * server_camera.zoom.y
			# if new_zoom_level_y > -0.01:
			# 	new_zoom_level_y = -0.01
			server_camera.zoom = Vector2(new_zoom_level_x, new_zoom_level_y)
		elif event.button_index == 5 and event.pressed:
			# Zoom Out
			var new_zoom_level_x: float = server_camera.zoom.x - 0.1 * server_camera.zoom.x
			if new_zoom_level_x < 0.01:
				new_zoom_level_x = 0.01
			var new_zoom_level_y: float = server_camera.zoom.y - 0.1 * server_camera.zoom.y
			if new_zoom_level_y < 0.01:
				new_zoom_level_y = 0.01
			server_camera.zoom = Vector2(new_zoom_level_x, new_zoom_level_y)

	if (
		event is InputEventMouseMotion
		and mouse_left_down
		and get_multiplayer_authority() == multiplayer.get_unique_id()
	):
		var move: Vector2 = Vector2()
		move.x = -event.relative.x / server_camera.zoom.x
		move.y = -event.relative.y / server_camera.zoom.y

		global_position += move