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
var spawned_debug_object: Node2D
var max_hand_distance: float = 25.0
var mouse_left_down: bool
var mine_cast: RayCast2D
var mining_speed: float = 0.1
var current_mining_time: float = 100
var ball: Resource = preload("res://items/disc/disc.tscn")
var held_item: Node


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
	#set_process(is_local)

	#
	set_process_input(is_local)
	set_process_internal(is_local)
	set_process_unhandled_input(is_local)
	set_process_unhandled_key_input(is_local)
	set_physics_process(is_local)
	set_physics_process_internal(is_local)
	#

	#spawned_debug_object = debug_object.instantiate()
	#get_node("/root").add_child(spawned_debug_object)


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

	if held_item:
		if is_mining:
			# TODO: Do not allow moving objects into terrain or through other characters,
			# much like the mining beam does not.
			held_item.set_position(to_local(mouse_position))
		elif is_multiplayer_authority():
			var held_item_name: String = held_item.name
			var held_item_global_position: Vector2 = held_item.global_position
			_drop_held_thing.rpc()
			Spawner.place_thing.rpc_id(1, held_item_name, held_item_global_position)


#Re-add when arms sometimes need to target other locations
#@export var ArmTargetPosition: Vector2

@rpc("call_local")
func _drop_held_thing() -> void:
	Helpers.log_print(
		str(held_item.name, " dropped by ", multiplayer.get_remote_sender_id()), "Cornflowerblue"
	)
	held_item.queue_free()
	held_item = null


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

		# spawned_debug_object = debug_object.instantiate()
		# get_node("/root").add_child(spawned_debug_object)
		# spawned_debug_object.global_position = arm_id_controller.global_position

		var arm_position: Vector2 = arm_id_controller.global_position
		var lower_arm_position: Vector2 = arm_lower_id_controller.global_position
		var mining_particle_distance: float = (
			clamp(
				clamp(arm_position.distance_to(mouse_position), 0, INTERACT_RANGE),
				0.0,
				mining_particles.global_position.distance_to(mouse_position)
			)
			/ 2.0
		)
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
			lower_arm_position,
			(
				lower_arm_position
				+ (
					arm_lower_id_controller.global_transform.x
					* clamp(lower_arm_position.distance_to(mouse_position), 0, INTERACT_RANGE)
				)
			)
		)
		# Globals.world_map.draw_line_on_map(
		# 	lower_arm_position,
		# 	(
		# 		lower_arm_position
		# 		+ (
		# 			arm_lower_id_controller.global_transform.x
		# 			* clamp(lower_arm_position.distance_to(mouse_position), 0, INTERACT_RANGE)
		# 		)
		# 	),
		# 	Color.RED
		# )  # For visualizing to debug
		query.exclude = [self]
		var result: Dictionary = space_state.intersect_ray(query)
		if result.size() > 0:
			var hit_point: Vector2 = result["position"]
			if result["collider"] is TileMap and not held_item:  # Do not mine while holding items
				Globals.world_map.mine_cell_at_position(hit_point - result["normal"])
			elif not held_item and result["collider"] is RigidBody2D and is_multiplayer_authority():
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
func spawn_player_held_thing(grabbed_item_name: String) -> void:
	var parsed_thing_name: Dictionary = Helpers.parse_thing_name(grabbed_item_name)
	Helpers.log_print(
		str(parsed_thing_name.name, " ", parsed_thing_name.id, " picked up by ", name),
		"Cornflowerblue"
	)
	# Spawn a local version for myself
	# This is similar to the thing spawning code in spawner()
	match parsed_thing_name.name:
		"Ball":
			held_item = ball.instantiate()
		_:
			printerr(
				"Invalid thing to spawn name into player held position: ", parsed_thing_name.name
			)
			return
	held_item.name = grabbed_item_name
	# Disable collision on held items, otherwise you can push others or yourself into the sky or the ground
	held_item.set_collision_layer_value(4, false)
	add_child(held_item)
