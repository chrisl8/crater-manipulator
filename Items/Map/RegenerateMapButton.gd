extends Button


func _ready() -> void:
	self.pressed.connect(self._button_pressed)


func _button_pressed() -> void:
	Globals.WorldMap.RegenerateMap()