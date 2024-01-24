extends Node2D

var IsLocal: bool = false

@export var Arm: Node2D

var CurrentTool: int = 1

const InteractRange: float = 200.0

@export var DebugObject: Resource = preload("res://player/Debug Object.tscn")

@export var MiningParticles: GPUParticles2D

@export var IsMining: bool = false

@export var MiningDistance: float = 0.0:
	set(new_value):
		MiningDistance = new_value
		UpdateMiningParticleLength()

@export var FlipPoint: Node2D

var SpawnedDebugObject: Node2D

@export var Flipped: bool = false

@export var ArmIKController: Node2D

func UpdateMiningParticleLength() -> void:
	var Extents: Vector3 = MiningParticles.process_material.get("emission_box_extents")
	Extents.x = MiningDistance

	MiningParticles.process_material.set("emission_box_extents", Extents)
	MiningParticles.process_material.set("emission_shape_offset", Vector3(MiningDistance, 0.0, 0.0))
	MiningParticles.look_at(MousePosition)


@export var Head: Node


func Initialize(Local: bool) -> void:
	IsLocal = Local
	#set_process(IsLocal)

	#
	set_process_input(IsLocal)
	set_process_internal(IsLocal)
	set_process_unhandled_input(IsLocal)
	set_process_unhandled_key_input(IsLocal)
	set_physics_process(IsLocal)
	set_physics_process_internal(IsLocal)
	#

	#SpawnedDebugObject = DebugObject.instantiate()
	#get_node("/root").add_child(SpawnedDebugObject)


var MaxHandDistance: float = 25.0


func _process(_delta: float) -> void:
	if IsLocal:
		MousePosition = get_global_mouse_position()

		Flipped = MousePosition.x < global_position.x
		'''
		if(Flipped):
			FlipPoint.scale.x = -1
		else:
			FlipPoint.scale.x = 1
		'''

		if Input.is_action_just_pressed(&"interact"):
			Globals.WorldMap.modify_cell(
				Vector2i(randi_range(-50, 50), randi_range(0, -50)), Vector2i(1, 1)
			)

		Arm.look_at(MousePosition)
		ArmTargetPosition.global_position = MousePosition
		'''
		ArmTargetPosition.global_position = (
			Arm.global_position
			+ (
				Arm.global_transform.x
				* (clamp(Arm.global_position.distance_to(MousePosition), 0, MaxHandDistance))
			)
		)
		'''

		CurrentMiningTime = clamp(CurrentMiningTime + _delta, 0.0, 100.0)
		if mouse_left_down:
			MineRaycast()
		IsMining = mouse_left_down

	else:
		'''
		if(Flipped):
			FlipPoint.scale.x = -1
		else:
			FlipPoint.scale.x = 1
		'''

		#Yes need this twice till refactor
		Arm.look_at(MousePosition)

	if IsMining:
		MiningParticles.look_at(MousePosition)

	ArmIKController.Target = MousePosition
	Head.look_at(MousePosition)
	MiningParticles.emitting = IsMining


@export var ArmTargetPosition: Node2D


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == 1 and event.is_pressed():
			if !mouse_left_down:
				LeftMouseClicked()
			mouse_left_down = true
		elif event.button_index == 1 and not event.is_pressed():
			mouse_left_down = false
		elif event.button_index == 2 and event.is_pressed():
			RightMouseClicked()


var mouse_left_down: bool
@export var MousePosition: Vector2

var MineCast: RayCast2D

var MiningSpeed: float = 0.1
var CurrentMiningTime: float = 100


func LeftMouseClicked() -> void:
	if CurrentTool == 1:
		pass
	pass


func MineRaycast() -> void:
	if CurrentMiningTime > MiningSpeed:
		CurrentMiningTime = 0.0
		var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state

		#var SpawnedDebugObject = DebugObject.instantiate()
		#get_node("/root").add_child(SpawnedDebugObject)
		#SpawnedDebugObject.global_position = Arm.global_position

		var ArmPosition: Vector2 = Arm.global_position
		var MiningParticleDistance: float = (
			clamp(
				clamp(ArmPosition.distance_to(MousePosition), 0, InteractRange),
				0.0,
				MiningParticles.global_position.distance_to(MousePosition)
			)
			/ 2.0
		)
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
			ArmPosition,
			(
				ArmPosition
				+ (
					Arm.global_transform.x
					* clamp(ArmPosition.distance_to(MousePosition), 0, InteractRange)
				)
			)
		)
		query.exclude = [self]
		var result: Dictionary = space_state.intersect_ray(query)
		if result.size() > 0:
			var HitPoint: Vector2 = result["position"]
			if result["collider"] is TileMap:
				Globals.WorldMap.MineCellAtPosition(HitPoint - result["normal"])
			MiningParticleDistance = MiningParticles.global_position.distance_to(HitPoint) / 2.0

		MiningDistance = MiningParticleDistance


func RightMouseClicked() -> void:
	Globals.WorldMap.place_cell_at_position(get_global_mouse_position())
	pass
