extends Button

@export var FocusParent: Node2D

func _ready() -> void:
	self.pressed.connect(self._button_pressed)


func _button_pressed() -> void:
	var TilePositions: Array = Globals.world_map.get_cell_positions()

	#print(TileData)

	var Position: Vector2i = TilePositions[randi_range(0,TilePositions.size())]
	#Missing 8 pixel offset but accurate enough for zoom
	FocusParent.position = Vector2(Position.x*16,Position.y*16)+Vector2(8,8)
	pass