extends Label

var time_elapsed: float = 0
var delay_time: float = 3


func _ready() -> void:
	text = "Welcome!"


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	time_elapsed += delta
	if time_elapsed > delay_time:
		time_elapsed = 0
		if text == "Welcome!":
			text = ""
			delay_time = 1
		elif not Globals.player_has_done.has("mine_a_block"):
			text = "Left click to mine a block."
		elif text == "Left click to mine a block.":
			text = ""
		elif not Globals.player_has_done.has("place_a_block"):
			text = "Right click to place a block."
		elif text == "Right click to place a block.":
			text = ""
		elif not Globals.player_has_done.has("press_craft_button"):
			text = "Press and hold 'c' to place an item."
		elif text == "Press and hold 'c' to place an item.":
			text = ""
		elif not Globals.player_has_done.has("scroll_crafting_items"):
			text = "Use mouse wheel to select item to craft.\nLeft click to place item.\nRelease 'c' to cancel item placing."
		elif (
			text
			== "Use mouse wheel to select item to craft.\nLeft click to place item.\nRelease 'c' to cancel item placing."
		):
			text = ""
