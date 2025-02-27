extends Node2D

const INTERACT_RANGE: float = 200.0

@export var debug_object: Resource = preload ("res://player/debug_object.tscn")
@export var mining_particles: GPUParticles2D
@export var left_hand_tool_is_active: bool = false
@export var right_hand_tool_is_active: bool = false
@export var mining_distance: float = 0.0:
	set(new_value):
		mining_distance = new_value
		update_mining_particle_length()
@export var flip_point: Node2D
@export var flipped: bool = false
@export var arm_id_controller: Node2D
@export var arm_lower_id_controller: Node2D
@export var head: Node2D
@export var legs_manager: Node2D
@export var antenna: Node2D
@export var mouse_position: Vector2
@export var left_hand_tool: Globals.Tools = Globals.Tools.MINE
@export var right_hand_tool: Globals.Tools = Globals.Tools.PLACE

var is_local: bool = false
var max_hand_distance: float = 25.0
var mouse_left_down: bool
var mouse_right_down: bool
var mine_cast: RayCast2D
var tool_speed: float = 0.1
var current_tool_raycast_time: float = 100
var ball: Resource = preload ("res://things/items/disc/disc.tscn")
var box: Resource = preload ("res://things/items/square/square.tscn")
var soup_machine: Resource = preload ("res://things/structures/soup_machine/soup_machine.tscn")
var controlled_item: PhysicsBody2D
var controlled_item_type: String = "Holding"
var controlled_item_clear_of_collisions: bool = false
var right_hand_modifier_active: bool = false

## Use this to save what tool to return to after using tools that need to auto-revert after use.
var return_to_this_left_hand_tool: Globals.Tools = Globals.Tools.MINE
var return_to_this_right_hand_tool: Globals.Tools = Globals.Tools.MINE

func update_mining_particle_length() -> void:
	var extents: Vector3 = mining_particles.process_material.get("emission_box_extents")
	extents.x = mining_distance

	mining_particles.process_material.set("emission_box_extents", extents)
	mining_particles.process_material.set("emission_shape_offset", Vector3(mining_distance, 0.0, 0.0))
	mining_particles.look_at(mouse_position)

## Set input key map based on settings in Godot Input Map
func update_tool_keys_display() -> void:
	for tool_name: String in Globals.Tools:
		tool_name = tool_name.to_lower()
		var input_events: Array = InputMap.action_get_events(tool_name.to_lower())
		if !input_events.is_empty():
			var keycode: int = DisplayServer.keyboard_get_keycode_from_physical(input_events[0].physical_keycode)
			var key_text: String = OS.get_keycode_string(keycode)
			# The Enter Input font keyboard keys are all lower-case. Upper-case denotes special keys.
			owner.get_node("Player Canvas/Keys/%s/Left/Key"% tool_name.to_pascal_case()).text = (key_text.to_lower())
			owner.get_node("Player Canvas/Keys/%s/Left/Key Pressed"% tool_name.to_pascal_case()).text = (key_text.to_lower())
			owner.get_node("Player Canvas/Keys/%s/Right/Key"% tool_name.to_pascal_case()).text = (key_text.to_lower())
			owner.get_node("Player Canvas/Keys/%s/Right/Key Pressed"% tool_name.to_pascal_case()).text = (key_text.to_lower())

func initialize(local: bool) -> void:
	is_local = local
	set_process_input(is_local)
	set_process_internal(is_local)
	set_process_unhandled_input(is_local)
	set_process_unhandled_key_input(is_local)
	set_physics_process(is_local)
	set_physics_process_internal(is_local)
	if is_local:
		update_tool_keys_display()
	else:
		owner.get_node("Player Canvas/Keys").visible = false

func _process(delta: float) -> void:
	if is_local:
		mouse_position = get_global_mouse_position()

		flipped = mouse_position.x < global_position.x
		if flipped:
			flip_point.scale.x = -1
		else:
			flip_point.scale.x = 1

		current_tool_raycast_time += delta
		if mouse_left_down:
			var clear_mouse_down: bool = tool_raycast(left_hand_tool)
			if clear_mouse_down:
				mouse_left_down = false
		# Because mouse_left_down is set in _input:
			# A. It is only set on the local player
			# B. It is not synced
			# So we transfer its value to left_hand_tool_is_active
			# in order to  is a networked variable to allow other players to see what this player is doing
			# Outside of this "if is_local" statement, we will always use the _is_active variable to
			# operate so that all players see the activity
		left_hand_tool_is_active = mouse_left_down
		if mouse_right_down:
			var clear_mouse_down: bool = tool_raycast(right_hand_tool)
			if clear_mouse_down:
				mouse_right_down = false
		# See left_hand_tool_is_active above for explanation
		right_hand_tool_is_active = mouse_right_down
	else:
		if flipped:
			flip_point.scale.x = -1
		else:
			flip_point.scale.x = 1

	legs_manager.flipped = flipped
	antenna.flipped = flipped

	if left_hand_tool_is_active and left_hand_tool == Globals.Tools.MINE:
		mining_particles.look_at(mouse_position)

	arm_id_controller.target = mouse_position
	head.look_at(mouse_position)
	mining_particles.emitting = (left_hand_tool_is_active and left_hand_tool == Globals.Tools.MINE)

	if controlled_item:
		# Note that mining and picking up things happens in the tool_raycast() function that was called earlier.

		# Note that by using the mouse position, with no restrictions, for placing items,
		# your "place distance" is limited only by your screen size and resolution!

		# TODO: Also let this work if PICKUP is selected.
		# TODO: We probably have to block some combinations, like you can't build with one hand and drag with the other can you?
		if controlled_item_type == "Building" or controlled_item_type == "Holding":
			if (is_multiplayer_authority()
			and ((left_hand_tool_is_active and left_hand_tool == Globals.Tools.BUILD)
			or (right_hand_tool_is_active and right_hand_tool == Globals.Tools.BUILD))
			and controlled_item_clear_of_collisions):
				if controlled_item_type == "Building":
					Globals.player_has_done.built_an_item = true
				var held_item_name: String = controlled_item.name
				var held_item_global_position: Vector2 = controlled_item.global_position
				if controlled_item.snaps:
					# Ensure it sticks to absolute integer positions!
					held_item_global_position = Vector2(int(held_item_global_position.x), int(held_item_global_position.y))
				Spawner.place_thing.rpc_id(1, held_item_name, held_item_global_position)
				_drop_held_thing.rpc()
				Globals.world_map.delete_drawing_canvas(held_item_name)
				if right_hand_tool_is_active and right_hand_tool == Globals.Tools.BUILD:
					right_hand_tool = return_to_this_right_hand_tool
				elif left_hand_tool_is_active and left_hand_tool == Globals.Tools.BUILD:
					left_hand_tool = return_to_this_left_hand_tool
				setKeyInputDisplay()
			else:
				var intersecting_tiles: Globals.MapTileSet = Globals.world_map.check_tile_location_and_surroundings(mouse_position, controlled_item.height_in_tiles, controlled_item.width_in_tiles, controlled_item.name)
				if controlled_item.snaps:
					controlled_item.set_position(to_local(intersecting_tiles.cell_aligned_center_position))
				else:
					controlled_item.set_position(to_local(mouse_position))
				controlled_item_clear_of_collisions = (intersecting_tiles.all_tiles_are_empty)

#Re-add when arms sometimes need to target other locations
#@export var ArmTargetPosition: Vector2

@rpc("call_local")
func _drop_held_thing() -> void:
	Helpers.log_print(str(controlled_item.name, " dropped by ", multiplayer.get_remote_sender_id()), "Cornflowerblue")
	if controlled_item:
		Globals.world_map.delete_drawing_canvas(controlled_item.name)
		controlled_item.queue_free()
		controlled_item = null

@rpc("call_local")
func de_spawn_placing_item() -> void:
	if controlled_item and controlled_item_type == "Building":
		# Don't allow us to de-spawn held items this way.
		Globals.world_map.delete_drawing_canvas(controlled_item.name)
		controlled_item.queue_free()
		controlled_item = null

## Set key input display based on currently active tool
func setKeyInputDisplay() -> void:
	# Left
	owner.get_node("Player Canvas/Keys/Mine/Left/Key").visible = left_hand_tool != Globals.Tools.MINE
	owner.get_node("Player Canvas/Keys/Mine/Left/Key Pressed").visible = left_hand_tool == Globals.Tools.MINE
	owner.get_node("Player Canvas/Keys/Place/Left/Key").visible = left_hand_tool != Globals.Tools.PLACE
	owner.get_node("Player Canvas/Keys/Place/Left/Key Pressed").visible = left_hand_tool == Globals.Tools.PLACE
	owner.get_node("Player Canvas/Keys/Build/Left/Key").visible = left_hand_tool != Globals.Tools.BUILD
	owner.get_node("Player Canvas/Keys/Build/Left/Key Pressed").visible = left_hand_tool == Globals.Tools.BUILD
	owner.get_node("Player Canvas/Keys/Destroy/Left/Key").visible = left_hand_tool != Globals.Tools.DESTROY
	owner.get_node("Player Canvas/Keys/Destroy/Left/Key Pressed").visible = left_hand_tool == Globals.Tools.DESTROY
	owner.get_node("Player Canvas/Keys/Pickup/Left/Key").visible = left_hand_tool != Globals.Tools.PICKUP
	owner.get_node("Player Canvas/Keys/Pickup/Left/Key Pressed").visible = left_hand_tool == Globals.Tools.PICKUP
	owner.get_node("Player Canvas/Keys/Drag/Left/Key").visible = left_hand_tool != Globals.Tools.DRAG
	owner.get_node("Player Canvas/Keys/Drag/Left/Key Pressed").visible = left_hand_tool == Globals.Tools.DRAG
	# Right
	owner.get_node("Player Canvas/Keys/Mine/Right/Key").visible = right_hand_tool != Globals.Tools.MINE
	owner.get_node("Player Canvas/Keys/Mine/Right/Key Pressed").visible = right_hand_tool == Globals.Tools.MINE
	owner.get_node("Player Canvas/Keys/Place/Right/Key").visible = right_hand_tool != Globals.Tools.PLACE
	owner.get_node("Player Canvas/Keys/Place/Right/Key Pressed").visible = right_hand_tool == Globals.Tools.PLACE
	owner.get_node("Player Canvas/Keys/Build/Right/Key").visible = right_hand_tool != Globals.Tools.BUILD
	owner.get_node("Player Canvas/Keys/Build/Right/Key Pressed").visible = right_hand_tool == Globals.Tools.BUILD
	owner.get_node("Player Canvas/Keys/Destroy/Right/Key").visible = right_hand_tool != Globals.Tools.DESTROY
	owner.get_node("Player Canvas/Keys/Destroy/Right/Key Pressed").visible = right_hand_tool == Globals.Tools.DESTROY
	owner.get_node("Player Canvas/Keys/Pickup/Right/Key").visible = right_hand_tool != Globals.Tools.PICKUP
	owner.get_node("Player Canvas/Keys/Pickup/Right/Key Pressed").visible = right_hand_tool == Globals.Tools.PICKUP
	owner.get_node("Player Canvas/Keys/Drag/Right/Key").visible = right_hand_tool != Globals.Tools.DRAG
	owner.get_node("Player Canvas/Keys/Drag/Right/Key Pressed").visible = right_hand_tool == Globals.Tools.DRAG

func _input(event: InputEvent) -> void:
	var previous_left_hand_tool: Globals.Tools = left_hand_tool
	var previous_right_hand_tool: Globals.Tools = right_hand_tool

	if event.is_action_pressed(&"right_hand_modifier"):
		right_hand_modifier_active = true
	elif event.is_action_released(&"right_hand_modifier"):
		right_hand_modifier_active = false
	elif event.is_action_released(&"mine"):
		if right_hand_modifier_active:
			right_hand_tool = Globals.Tools.MINE
		else:
			left_hand_tool = Globals.Tools.MINE
		Globals.player_has_done.returned_to_mining_mode = true
	elif event.is_action_released(&"place"):
		if right_hand_modifier_active:
			right_hand_tool = Globals.Tools.PLACE
		else:
			left_hand_tool = Globals.Tools.PLACE
	elif event.is_action_released(&"build"):
		if right_hand_modifier_active:
			if previous_right_hand_tool != Globals.Tools.BUILD:
				return_to_this_right_hand_tool = previous_right_hand_tool
			right_hand_tool = Globals.Tools.BUILD
		else:
			if previous_left_hand_tool != Globals.Tools.BUILD:
				return_to_this_left_hand_tool = previous_left_hand_tool
			left_hand_tool = Globals.Tools.BUILD
		Globals.player_has_done.press_build_button = true
		owner.spawn_item()
	elif event.is_action_released(&"pickup"):
		if right_hand_modifier_active:
			right_hand_tool = Globals.Tools.PICKUP
		else:
			left_hand_tool = Globals.Tools.PICKUP
	elif event.is_action_released(&"drag"):
		if right_hand_modifier_active:
			right_hand_tool = Globals.Tools.DRAG
		else:
			left_hand_tool = Globals.Tools.DRAG

	setKeyInputDisplay()

	if event is InputEventMouseButton:
		if event.button_index == 1:
			mouse_left_down = event.is_pressed()
		elif event.button_index == 2:
			mouse_right_down = event.is_pressed()

		# This is where using the scroll wheel in build mode cycles through items
		if left_hand_tool == Globals.Tools.BUILD or right_hand_tool == Globals.Tools.BUILD:
			Globals.player_has_done.scroll_crafting_items = true
			if event.button_index == 4 and event.pressed:
				# Scroll Up
				owner.player_spawn_item_next += 1
				if owner.player_spawn_item_next > owner.player_spawnable_items.size() - 1:
					owner.player_spawn_item_next = 0
				de_spawn_placing_item.rpc()
				owner.spawn_item()
			elif event.button_index == 5 and event.pressed:
				# Scroll Down
				owner.player_spawn_item_next -= 1
				if owner.player_spawn_item_next < 0:
					owner.player_spawn_item_next = (owner.player_spawnable_items.size() - 1)
				de_spawn_placing_item.rpc()
				owner.spawn_item()

	if previous_left_hand_tool != left_hand_tool:
		# Tool changed
		if previous_left_hand_tool == Globals.Tools.BUILD:
			de_spawn_placing_item.rpc()
	if previous_right_hand_tool != right_hand_tool:
		# Tool changed
		if previous_right_hand_tool == Globals.Tools.BUILD:
			de_spawn_placing_item.rpc()

func tool_raycast(active_tool: Globals.Tools) -> bool:
	# NOTE: If you don't want "auto-fire" on a mouse click for a given action,
	# then you can set clear_mouse_down to true.
	var clear_mouse_down: bool = false
	if current_tool_raycast_time > tool_speed:
		current_tool_raycast_time = 0.0
		var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
		var arm_position: Vector2 = arm_id_controller.global_position
		var mining_particle_distance: float = clamp(clamp(arm_position.distance_to(mouse_position), 0, INTERACT_RANGE), 0.0, mining_particles.global_position.distance_to(mouse_position)) / 2.0
		var target_position: Vector2 = arm_position + ((mouse_position - arm_position).normalized() * clamp(arm_position.distance_to(mouse_position), 0, INTERACT_RANGE))
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(arm_position, target_position)
		query.exclude = [self]
		var result: Dictionary = space_state.intersect_ray(query)

		# Here is the logic for "what to do with a raycast, depending on what "tool" is in your hand.
		# I think this logic could be improved a lot, but there is no "simple" way to both make the player
		# experience good and make this logic easy to read.
		# So just document it well and reorganize it later if it becomes more clear how to better organize it
		# without also duplicating a lot of code.

		# Note that the "Building" and/or "dropping" of build/held items is done in the _process() function AFTER this
		# function is called.
		# This can be hard to keep in mind, but the reason is that mining and picking up depend on the raycast position,
		# while dropping and placing only depend on the mouse position.
		# Although, it could make sense to change that and raycast to the position where a thing could be placed, which would
		# make it harder to place objects in terrain, and on the other side of walls.

		if active_tool == Globals.Tools.MINE:
			Globals.world_map.draw_temp_line_on_map(arm_position, target_position, Color.RED)
			if result.size() > 0 and result["collider"] is TileMap:
				Globals.world_map.mine_cell_at_position(result["position"] - result["normal"])
		elif active_tool == Globals.Tools.PLACE:
			Globals.world_map.draw_temp_line_on_map(arm_position, target_position, Color.BLUE)
			if result.size() < 1:
				# NOTE: Previously you could "replace" a block, but now you cannot since it only allows placing if the raycast finds NOTHING.
				# However, this does prevent building "through walls and floors".
				Globals.world_map.place_cell_at_position(get_global_mouse_position())
		elif active_tool == Globals.Tools.PICKUP:
			if result.size() > 0 and not controlled_item and result["collider"] is PhysicsBody2D: # You are ALREADY holding an item, you cannot hold two items.  # You can currently only pick up RigidBodies.
				var body: Node = result["collider"]
				if body.has_method("grab"): # The RigidBody must have a "grab" method to be able to be picked up.
					body.grab.rpc_id(1)
					# Reset now so it does not immediately drop.
					# This means that you don't "release" to drop the item, but click again.
					# The benefit of this is that the game can track overlaps and not allow you to drop the item if it is colliding with terrain.
					# We couldn't prevent a user from releasing the mouse button, but we can ignore a click if the object is colliding.
					clear_mouse_down = true

		if result.size() > 0:
			# This is always set, even if we don't use it.
			mining_particle_distance = (mining_particles.global_position.distance_to(result["position"]) / 2.0)

		## This is a synced variable used by other players to see your mining activity.
		mining_distance = mining_particle_distance

	return clear_mouse_down

# Spawning and dropping the "thing" must be an RPC because all "copies" of the player
# must do this to sync the view of them holding/not holding the thing across players views
# of this player.
@rpc("any_peer", "call_local")
func spawn_player_controlled_thing(thing_position: Vector2, thing_rotation: float, controlled_item_name: String, spawned_item_type: String="Holding") -> void:
	if controlled_item:
		# We can never control a new thing if we are already controlling something
		# Whoever called this should have called de_spawn_placing_item() first if they were serious
		return
	var parsed_thing_name: Dictionary = Helpers.parse_thing_name(controlled_item_name)
	var action: String = "picked up"
	if spawned_item_type == "Building":
		action = "being built"
	Helpers.log_print(str(parsed_thing_name.name, " ", parsed_thing_name.id, " ", action, " by ", name), "Cornflowerblue")
	# Spawn a local version for myself
	# This is similar to the thing spawning code in spawner()
	match parsed_thing_name.name:
		"Ball":
			controlled_item = ball.instantiate()
		"Box":
			controlled_item = box.instantiate()
		"SoupMachine":
			controlled_item = soup_machine.instantiate()
		_:
			printerr("Invalid thing to spawn name into player held position: ", parsed_thing_name.name)
			return
	controlled_item_type = spawned_item_type
	controlled_item.name = controlled_item_name

	if spawned_item_type == "Holding":
		controlled_item.set_spawn_location(thing_position, thing_rotation)

	controlled_item.global_position = thing_position
	controlled_item.global_rotation = thing_rotation

	# Disable collision on held items, otherwise you can push others or yourself into the sky or the ground
	controlled_item.set_collision_layer_value(4, false)
	add_child(controlled_item)
