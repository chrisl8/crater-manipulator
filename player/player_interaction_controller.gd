extends Node2D

const INTERACT_RANGE: float = 200.0

@export var debug_object: Resource = preload("res://player/debug_object.tscn")
@export var mining_particles: GPUParticles2D
@export var left_hand_tool_is_active: bool = false
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
var mine_cast: RayCast2D
var tool_speed: float = 0.1
var current_tool_raycast_time: float = 100
var ball: Resource = preload("res://items/disc/disc.tscn")
var box: Resource = preload("res://items/square/square.tscn")
var soup_machine: Resource = preload("res://items/soup_machine/soup_machine.tscn")
var controlled_item: RigidBody2D
var controlled_item_type: String = "Holding"
var controlled_item_clear_of_collisions: bool = false


func update_mining_particle_length() -> void:
	var extents: Vector3 = mining_particles.process_material.get("emission_box_extents")
	extents.x = mining_distance

	mining_particles.process_material.set("emission_box_extents", extents)
	mining_particles.process_material.set(
		"emission_shape_offset", Vector3(mining_distance, 0.0, 0.0)
	)
	mining_particles.look_at(mouse_position)


func initialize(local: bool) -> void:
	is_local = local
	set_process_input(is_local)
	set_process_internal(is_local)
	set_process_unhandled_input(is_local)
	set_process_unhandled_key_input(is_local)
	set_physics_process(is_local)
	set_physics_process_internal(is_local)
	if is_local:
		owner.get_node("Player Canvas/Tools/Current").text = "Left: Mine\nRight: Place Block"


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
			tool_raycast()
		left_hand_tool_is_active = mouse_left_down

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
		# Picked Up items drop when you release the mouse button because they "exist" already.
		# Build items are placed when you click the left mouse button because they did not previously "exist".

		# Note that mining and picking up things happens in the tool_raycast() function that was called earlier._add_constant_central_force

		# Note that by using the mouse position, with no restrictions, for placing items, your "place distance" is limited only by your screen size and resolution!

		if controlled_item_type == "Building" || controlled_item_type == "Holding":
			if (
				left_hand_tool_is_active
				and is_multiplayer_authority()
				and controlled_item_clear_of_collisions
			):
				if controlled_item_type == "Building":
					Globals.player_has_done.built_an_item = true
				var held_item_name: String = controlled_item.name
				var held_item_global_position: Vector2 = controlled_item.global_position
				Spawner.place_thing.rpc_id(1, held_item_name, held_item_global_position)
				_drop_held_thing.rpc()
				Globals.world_map.delete_drawing_canvas(held_item_name)
			else:
				controlled_item.set_position(to_local(mouse_position))
				var intersecting_tiles: Globals.MapTileSet = (
					Globals
					. world_map
					. check_tile_location_and_surroundings(
						mouse_position,
						controlled_item.height_in_tiles,
						controlled_item.width_in_tiles,
						controlled_item.name
					)
				)
				controlled_item_clear_of_collisions = (intersecting_tiles.all_tiles_are_empty)


#Re-add when arms sometimes need to target other locations
#@export var ArmTargetPosition: Vector2

@rpc("call_local")
func _drop_held_thing() -> void:
	Helpers.log_print(
		str(controlled_item.name, " dropped by ", multiplayer.get_remote_sender_id()),
		"Cornflowerblue"
	)
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


func _input(event: InputEvent) -> void:
	var previous_left_hand_tool: Globals.Tools = left_hand_tool
	if event.is_action_released(&"build"):
		left_hand_tool = Globals.Tools.BUILD
		owner.get_node("Player Canvas/Tools/Current").text = "Left: Build\nRight: Place Block"
		Globals.player_has_done.press_build_button = true
		owner.spawn_item()
	elif event.is_action_released(&"mine"):
		owner.get_node("Player Canvas/Tools/Current").text = "Left: Mine\nRight: Place Block"
		if left_hand_tool != Globals.Tools.MINE:
			Globals.player_has_done.returned_to_mining_mode = true
		left_hand_tool = Globals.Tools.MINE
	elif event.is_action_released(&"pickup"):
		owner.get_node("Player Canvas/Tools/Current").text = "Left: Pick Up\nRight: Place Block"
		left_hand_tool = Globals.Tools.PICKUP
	elif event.is_action_released(&"drag"):
		owner.get_node("Player Canvas/Tools/Current").text = "Left: Drag\nRight: Place Block"
		left_hand_tool = Globals.Tools.DRAG
	if event is InputEventMouseButton:
		if event.button_index == 1 and event.is_pressed():
			mouse_left_down = true
		elif event.button_index == 1 and not event.is_pressed():
			mouse_left_down = false
		elif event.button_index == 2 and event.is_pressed():
			right_mouse_clicked()

		# This is where using the scroll wheel in build mode cycles through items
		if left_hand_tool == Globals.Tools.BUILD:
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


func tool_raycast() -> void:
	if current_tool_raycast_time > tool_speed:
		current_tool_raycast_time = 0.0
		var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
		var arm_position: Vector2 = arm_id_controller.global_position
		var mining_particle_distance: float = (
			clamp(
				clamp(arm_position.distance_to(mouse_position), 0, INTERACT_RANGE),
				0.0,
				mining_particles.global_position.distance_to(mouse_position)
			)
			/ 2.0
		)
		var target_position: Vector2 = (
			arm_position
			+ (
				(mouse_position - arm_position).normalized()
				* clamp(arm_position.distance_to(mouse_position), 0, INTERACT_RANGE)
			)
		)
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
			arm_position, target_position
		)
		if left_hand_tool == Globals.Tools.MINE:  # Only show the "laser" if mining
			# LASER DRILL!!! ==>-----
			Globals.world_map.draw_temp_line_on_map(arm_position, target_position, Color.RED)
		query.exclude = [self]
		var result: Dictionary = space_state.intersect_ray(query)
		if result.size() > 0:
			var hit_point: Vector2 = result["position"]

			# Here is the logic for "what to do with a raycast, depending on what "tool" is in your hand.
			# I think this logic could be improved a lot, but there is no "simple" way to both make the player
			# experience good and make this logic easy to read.
			# So just document it well and reorganize it later if it becomes more clear how to better organize it
			# without also duplicating a lot of code.

			# Note that the "Building" and/or "dropping" of build/held items is done in the _process() function AFTER this
			# function is called.
			# This can be hard to keep in mind, but the reason is that mining and picking up depend on the raycast position,
			# while dropping and placing only depend on the mouse position.

			if left_hand_tool == Globals.Tools.MINE:
				if result["collider"] is TileMap and not controlled_item:  # Do not mine while holding items, no matter what
					Globals.world_map.mine_cell_at_position(hit_point - result["normal"])
			elif left_hand_tool == Globals.Tools.PICKUP:
				if not controlled_item and result["collider"] is RigidBody2D:  # You are ALREADY holding an item, you cannot hold two items.  # You can currently only pick up RigidBodies.
					var body: Node = result["collider"]
					if body.has_method("grab"):  # The RigidBody must have a "grab" method to be able to be picked up.
						body.grab.rpc_id(1)
						mouse_left_down = false  # Reset now so it does not immediately drop.

			# This is always set, even if we don't use it.
			mining_particle_distance = (
				mining_particles.global_position.distance_to(hit_point) / 2.0
			)

		## This is a synced variable used by other players to see your mining activity.
		mining_distance = mining_particle_distance


func right_mouse_clicked() -> void:
	# This function is terribly simple compared to the way the left mouse button works,
	# simply due to us not having allowed swapping tools in the right hand yet,
	# but I do plan to change that in the future.

	# Note that because we just use the mouse position:
	# 1. The distance at which you can place is only restricted by the size and resolution of your screen.
	# 2. You can place blocks in areas that you cannot access (no ray trace check)
	# This will probably be addressed when we update the right mouse button to allow tool swapping and make it more like left click.

	Globals.world_map.place_cell_at_position(get_global_mouse_position())


# Spawning and dropping the "thing" must be an RPC because all "copies" of the player
# must do this to sync the view of them holding/not holding the thing across players views
# of this player.
@rpc("any_peer", "call_local")
func spawn_player_controlled_thing(
	thing_position: Vector2,
	thing_rotation: float,
	controlled_item_name: String,
	spawned_item_type: String = "Holding"
) -> void:
	if controlled_item:
		# We can never control a new thing if we are already controlling something
		# Whoever called this should have called de_spawn_placing_item() first if they were serious
		return
	var parsed_thing_name: Dictionary = Helpers.parse_thing_name(controlled_item_name)
	var action: String = "picked up"
	if spawned_item_type == "Building":
		action = "being built"
	Helpers.log_print(
		str(parsed_thing_name.name, " ", parsed_thing_name.id, " ", action, " by ", name),
		"Cornflowerblue"
	)
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
			printerr(
				"Invalid thing to spawn name into player held position: ", parsed_thing_name.name
			)
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
