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
		elif (
			not Globals.player_has_done.has("mine_a_block")
			and owner.get_node("Interaction Controller").left_hand_tool == "Mine"
		):
			text = "Left click to mine a block."
		elif (
			not Globals.player_has_done.has("place_a_block")
			and owner.get_node("Interaction Controller").right_hand_tool == "Place"
		):
			text = "Right click to place a block."
		elif not Globals.player_has_done.has("press_build_button"):
			text = "Press 'b' to enter Build mode."
		elif (
			not Globals.player_has_done.has("scroll_crafting_items")
			and owner.get_node("Interaction Controller").left_hand_tool == "Build"
		):
			text = "Use mouse wheel to select item to build."
		elif (
			not Globals.player_has_done.has("built_an_item")
			and owner.get_node("Interaction Controller").left_hand_tool == "Build"
		):  # and in build mode
			text = "Left click to place an item."
		elif (
			not Globals.player_has_done.has("returned_to_mining_mode")
			and owner.get_node("Interaction Controller").left_hand_tool != "Mine"
		):
			# TODO: Something is broken, it mines, but the tool is still Build.
			# TODO: Should it "auto return" to mine or just stay in build with a new item?
			# TODO: Highlight on screen which tool is in use.
			print(owner.get_node("Interaction Controller").left_hand_tool)
			text = "Press 'v' to return to mining mode."
		else:
			text = ""
