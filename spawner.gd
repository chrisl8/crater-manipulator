extends Node

var ball: Resource = preload("res://things/items/disc/disc.tscn")
var box: Resource = preload("res://things/items/square/square.tscn")
var soup_machine: Resource = preload("res://things/structures/soup_machine/soup_machine.tscn")

var done_once: bool = false

@onready var things_spawning_node: Node = get_node("../Main/Things")

# Called by players to ask Server to place a held item.
@rpc("any_peer", "call_remote")
func place_thing(node_name: String, placement_position: Vector2 = Vector2.ZERO) -> void:
	if Globals.is_server:  # this should only be called TO the server, but just in case someone calls it incorrectly
		var parsed_node_name: Dictionary = Helpers.parse_thing_name(node_name)
		thing(parsed_node_name.name, placement_position, parsed_node_name.id)


## Ask the server to spawn a thing
## thing_name is a type of thing that must exist in the list of known things names. It really should be an enum.
## spawn_position can be left blank, which will just spawn it at 0, 0
## id is an integer for you to track it with, if you don't care to make one, pass in -1 (or leave it default) and a random ID will be given
@rpc("any_peer", "call_remote", "reliable")
func thing(thing_name: String, spawn_position: Vector2 = Vector2.ZERO, id: int = -1) -> void:
	if id < 0:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		id = rng.randi()
	var thing_name_to_spawn: String = str(thing_name, "-", id)
	var existing_thing: Node = things_spawning_node.get_node_or_null(thing_name_to_spawn)
	if not existing_thing:
		var new_thing: Node
		match thing_name:
			"Ball":
				new_thing = ball.instantiate()
			"Box":
				new_thing = box.instantiate()
			"SoupMachine":
				new_thing = soup_machine.instantiate()
			_:
				printerr("Invalid thing to spawn name: ", thing_name)
				return
		new_thing.name = str(thing_name_to_spawn)
		if spawn_position:
			new_thing.spawn_position = spawn_position
		Helpers.log_print(str("Spawning ", thing_name_to_spawn, " at ", spawn_position), "yellow")
		if new_thing.snaps:
			new_thing.freeze = true
		things_spawning_node.add_child(new_thing)
