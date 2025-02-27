extends Node

## Tool types
## Note that you BUILD items and structures, but you PLACE blocks
enum Tools {EMPTY, MINE, PLACE, BUILD, DESTROY, PICKUP, DRAG}
enum ItemTypes {FREE, STRUCTURE}

var server_config: Dictionary = {}
var server_player_save_data_file_name: String = "user://server_player_data.dat"
var player_save_data: Dictionary = {}
var is_server: bool = false
var force_client: bool = false
var shutdown_server: bool = false
var local_debug_instance_number: int = -1
var url: String
var shutdown_in_progress: bool = false

## Used to know if the client has ever connected before when performing a retry
var has_connected_once: bool = false
var connection_failed_message: String = "Connection Failed!"
var world_map: Node
var initial_map_load_finished: bool = false
var resource_ids: Dictionary = {"Stone": 0, "Red Ore": 1}
var resource_names: Dictionary = {}
var has_built_resources_dictionary: bool = false
var players: Dictionary = {}
var player_has_done: Dictionary = {}

## Map Tile Set - A static class used to pass around a set of map tiles with general data about them.
class MapTileSet:
	var all_tiles_are_empty: bool = false
	var tile_list: Array[Vector2i] = []
	var tile_content: Dictionary = {}
	var cell_aligned_center_position: Vector2

func get_resource_name(id: int) -> String:
	build_resources_dictionaries()
	var resource_name: String
	if resource_names.has(id):
		resource_name = resource_names[id]
	return resource_name

func get_resource_id(resource_name: String) -> Array:
	build_resources_dictionaries()
	return resource_ids[resource_name]

func build_resources_dictionaries() -> void:
	if !has_built_resources_dictionary:
		for key: String in resource_ids.keys():
			resource_names[resource_ids[key]] = key
		has_built_resources_dictionary = true

func get_is_cell_mineable(cell: Vector2i) -> bool:
	#In future should check array/dictionary of white or black listed tiles
	return cell.y != 2
