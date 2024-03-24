extends Label

var time_elapsed: float = 0
var delay_time: float = 3
var is_local: bool = false


func _process(delta: float) -> void:
	time_elapsed += delta
	if time_elapsed > delay_time:
		time_elapsed = 0
		if text == "Welcome!":
			text = ""
			delay_time = 1
		elif (
			not Globals.player_has_done.has("mine_a_block")
			and (
				owner.get_node("Interaction Controller").left_hand_tool
				== Globals.Tools.MINE
			)
		):
			text = "Left click to mine a block."
		elif (
			not Globals.player_has_done.has("place_a_block")
			and (
				owner.get_node("Interaction Controller").right_hand_tool
				== Globals.Tools.BUILD
			)
		):
			text = "Right click to place a block."
		elif not Globals.player_has_done.has("press_build_button"):
			text = "Press 'b' to enter Build mode."
		elif (
			not Globals.player_has_done.has("scroll_crafting_items")
			and (
				owner.get_node("Interaction Controller").left_hand_tool
				== Globals.Tools.BUILD
			)
		):
			text = "Use mouse wheel to select item to build."
		elif (
			not Globals.player_has_done.has("built_an_item")
			and (
				owner.get_node("Interaction Controller").left_hand_tool
				== Globals.Tools.BUILD
			)
		):  # and in build mode
			text = "Left click to place an item."
		elif (
			not Globals.player_has_done.has("returned_to_mining_mode")
			and (
				owner.get_node("Interaction Controller").left_hand_tool
				!= Globals.Tools.MINE
			)
		):
			text = "Press 'v' to return to mining mode."
		else:
			text = ""


func initialize(local: bool) -> void:
	is_local = local
	set_process(is_local)
	if is_local:
		text = "Welcome!"
