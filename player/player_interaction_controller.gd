extends Node2D

const INTERACT_RANGE: float = 200.0

@export var debug_object: Resource = preload("res://player/debug_object.tscn")
@export var mining_particles: GPUParticles2D
@export var is_mining: bool = false
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

var is_local: bool = false
var current_tool: int = 1
var max_hand_distance: float = 25.0
var mouse_left_down: bool
var mine_cast: RayCast2D
var mining_speed: float = 0.1
var current_mining_time: float = 100
var ball: Resource = preload("res://items/disc/disc.tscn")
var box: Resource = preload("res://items/square/square.tscn")
var soup_machine: Resource = preload("res://items/soup_machine/soup_machine.tscn")
var controlled_item: RigidBody2D
var controlled_item_type: String = "Held"
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


func _process(delta: float) -> void:
	if is_local:
		mouse_position = get_global_mouse_position()

		flipped = mouse_position.x < global_position.x
		if flipped:
			flip_point.scale.x = -1
		else:
			flip_point.scale.x = 1

		current_mining_time += delta
		if mouse_left_down:
			mine_raycast()
		is_mining = mouse_left_down

	else:
		if flipped:
			flip_point.scale.x = -1
		else:
			flip_point.scale.x = 1

	legs_manager.flipped = flipped
	antenna.flipped = flipped

	if is_mining:
		mining_particles.look_at(mouse_position)

	arm_id_controller.target = mouse_position
	head.look_at(mouse_position)
	mining_particles.emitting = is_mining

	if controlled_item:
		# Held items drop when you release the mouse button.
		# Placed items are placed when you click the left mouse button.
		if controlled_item_type == "Held":
			if is_mining:
				#controlled_item.set_position(to_local(mouse_position))
				#controlled_item.set_position(controlled_item.global_position)
				#if(randf() > 0.99):
				#	controlled_item.set_position(to_local(mouse_position))

				#if(is_local):

				#controlled_item.add_constant_central_force(controlled_item.global_position-to_local(mouse_position))
				#print(to_local(mouse_position) - controlled_item.global_position)
				#print(controlled_item.global_position.distance_to(mouse_position))
				#print(controlled_item.global_position,mouse_position,(mouse_position - controlled_item.global_position))

				var LocationA = mouse_position
				var LocationB = controlled_item.to_global(controlled_item.center_of_mass)

				Globals.world_map.draw_temp_line_on_map(LocationA, LocationB, Color.CYAN)
				var Force = (LocationA - LocationB).normalized() * 100000.0

				controlled_item.constant_force = (Force)
				#controlled_item.x
				#controlled_item.apply_central_force ((controlled_item.global_position-to_local(mouse_position)).normalized()*100)
				pass

			elif is_multiplayer_authority():
				var held_item_name: String = controlled_item.name
				var held_item_global_position: Vector2 = controlled_item.global_position
				Spawner.place_thing.rpc_id(1, held_item_name, held_item_global_position)
				_drop_held_thing.rpc()
		elif controlled_item_type == "Placing":
			if is_mining and is_multiplayer_authority() and controlled_item_clear_of_collisions:
				var held_item_name: String = controlled_item.name
				var held_item_global_position: Vector2 = controlled_item.global_position
				Spawner.place_thing.rpc_id(1, held_item_name, held_item_global_position)
				_drop_held_thing.rpc()
				Globals.world_map.delete_drawing_canvas(held_item_name)
			else:
				controlled_item.set_position(to_local(mouse_position))
				var intersecting_tiles: Globals.MapTileSet = (
					Globals.world_map.check_tile_location_and_surroundings(mouse_position)
				)
				controlled_item_clear_of_collisions = intersecting_tiles.all_tiles_are_empty
				Globals.world_map.erase_drawing_canvas(controlled_item.name)
				if not controlled_item_clear_of_collisions:
					for cell: Vector2i in intersecting_tiles.tile_list:
						Globals.world_map.highlight_cell_at_map_position(
							cell, Color(255.0, 0.0, 0.0, 0.50), controlled_item.name
						)
				else:
					# TODO: Only do this if it is the "kind of item" that needs to do this (soup machines, not balls)
					for cell: Vector2i in intersecting_tiles.tile_list:
						Globals.world_map.highlight_cell_at_map_position(
							cell, Color(0.0, 255.0, 0.0, 0.50), controlled_item.name
						)

				##print(colliding_tiles.all_tiles_are_empty)
				#print(colliding_tiles.tile_list)
				# if not Globals.world_map.check_tile_location_and_surroundings(mouse_position):
				# 	#Globals.world_map.highlight_cell_at_global_position(mouse_position, Color.RED)
				# 	Helpers.log_print("Nope")


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
	if controlled_item and controlled_item_type == "Placing":
		# Don't allow us to de-spawn held items this way.
		Globals.world_map.delete_drawing_canvas(controlled_item.name)
		controlled_item.queue_free()
		controlled_item = null


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == 1 and event.is_pressed():
			if !mouse_left_down:
				left_mouse_clicked()
			mouse_left_down = true
		elif event.button_index == 1 and not event.is_pressed():
			mouse_left_down = false
		elif event.button_index == 2 and event.is_pressed():
			right_mouse_clicked()


func left_mouse_clicked() -> void:
	if current_tool == 1:
		pass


func mine_raycast() -> void:
	if current_mining_time > mining_speed:
		current_mining_time = 0.0
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
		Globals.world_map.draw_temp_line_on_map(arm_position, target_position, Color.RED)  # For visualizing to debug
		query.exclude = [self]
		var result: Dictionary = space_state.intersect_ray(query)
		if result.size() > 0:
			var hit_point: Vector2 = result["position"]
			if result["collider"] is TileMap and not controlled_item:  # Do not mine while holding items
				Globals.world_map.mine_cell_at_position(hit_point - result["normal"])
			elif (
				not controlled_item
				and result["collider"] is RigidBody2D
				and is_multiplayer_authority()
			):
				var body: Node = result["collider"]
				if body.has_method("grab"):
					body.grab.rpc_id(1)
			mining_particle_distance = mining_particles.global_position.distance_to(hit_point) / 2.0

		mining_distance = mining_particle_distance


func right_mouse_clicked() -> void:
	Globals.world_map.place_cell_at_position(get_global_mouse_position())


# Spawning and dropping the "thing" must be an RPC because all "copies" of the player
# must do this to sync the view of them holding/not holding the thing across players views
# of this player.
@rpc("any_peer", "call_local")
func spawn_player_controlled_thing(
	thing_position: Vector2,
	thing_rotation: float,
	controlled_item_name: String,
	spawned_item_type: String = "Held"
) -> void:
	if controlled_item:
		# We can never control a new thing if we are already controlling something
		# Whoever called this should have called de_spawn_placing_item() first if they were serious
		return
	var parsed_thing_name: Dictionary = Helpers.parse_thing_name(controlled_item_name)
	var action: String = "picked up"
	if spawned_item_type == "Placing":
		action = "being placed"
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
	if spawned_item_type == "Held":
		controlled_item.SetSpawnLocation(thing_position, thing_rotation)

	controlled_item.global_position = thing_position
	controlled_item.global_rotation = thing_rotation

	# Disable collision on held items, otherwise you can push others or yourself into the sky or the ground
	controlled_item.set_collision_layer_value(4, false)
	add_child(controlled_item)
