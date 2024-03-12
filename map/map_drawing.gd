extends Node2D

var rectangles_to_draw: Dictionary = {}
var rectangles_to_draw_size: int = 0

var lines_to_draw: Dictionary = {}
var lines_to_draw_size: int = 0
var update_draw: bool = false

var temp: bool = false

func _process(_delta: float) -> void:
	if (
		update_draw
		|| rectangles_to_draw.size() != rectangles_to_draw_size
		|| lines_to_draw.size() != lines_to_draw_size
	):
		update_draw = false
		rectangles_to_draw_size = rectangles_to_draw.size()
		lines_to_draw_size = lines_to_draw.size()
		queue_redraw()


func _draw() -> void:
	if rectangles_to_draw.size() > 0:
		for key: Rect2 in rectangles_to_draw.keys():
			var color: Color = Color.RED
			if rectangles_to_draw[key].has("color"):
				color = rectangles_to_draw[key].color
			draw_rect(key, color)
	if lines_to_draw.size() > 0:
		# Narrower lines tend to disappear at discreet zoom levels, although they are easier to spot which pixel they came from/went to.
		# This could be configurable in the data.
		var line_width: float = 1.0
		for key: String in lines_to_draw.keys():
			var color: Color = Color.RED
			if lines_to_draw[key].has("color"):
				color = lines_to_draw[key].color
			draw_line(lines_to_draw[key].from, lines_to_draw[key].to, color, line_width)
	if(temp):
		rectangles_to_draw.clear()
		lines_to_draw.clear()
		#queue_redraw()
		temp = false