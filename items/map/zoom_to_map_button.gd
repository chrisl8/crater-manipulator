extends Button

@export var focus_parent: Node2D


func _ready() -> void:
	self.pressed.connect(self._button_pressed)


func _button_pressed() -> void:
	var tile_positions: Array = Globals.world_map.get_cell_positions()
	var new_position: Vector2i = tile_positions[randi_range(0, tile_positions.size())]
	#Missing 8 pixel offset but accurate enough for zoom
	focus_parent.position = Vector2(new_position.x * 16, new_position.y * 16) + Vector2(8, 8)
