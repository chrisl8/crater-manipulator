class_name RigidBody2dItem
extends RigidBody2D

@export var spawn_position: Vector2
@export var width_in_tiles: int = 2
@export var height_in_tiles: int = 2
@export var item_type: Globals.ItemTypes = Globals.ItemTypes.FREE
@export var snaps: bool = false

var waiting_to_set_location: bool = false
var force_set_position: Vector2
var force_set_rotation: float

#Unfortunately Godot does not provide a system for physics/transform reconciliation, direct access to the physics state, or a state update request system.
#So the only option is this cyclic state update check. Hopefully it isn't too expensive.
#The initial position can not be set either because of how the spawning system work for network synchronizers.

#This is hard baked enough into Godot's methodology that I assume it is intended behavior, and consequently this will need to be broken out into it's own script
#to allow this behavior to be easily added to objects, as it is critical for physics control.


func set_spawn_location(new_position: Vector2, new_rotation: float) -> void:
	force_set_position = new_position
	force_set_rotation = new_rotation
	waiting_to_set_location = true


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if waiting_to_set_location:
		state.transform = Transform2D(force_set_rotation, force_set_position)
		waiting_to_set_location = false
