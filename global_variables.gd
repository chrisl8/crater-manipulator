extends Node

var server_config: Dictionary = {}
var server_player_save_data_file_name: String = "user://server_player_data.dat"
var player_save_data: Dictionary = {}
var is_server: bool = false
var force_client: bool = false
var shutdown_server: bool = false
var local_debug_instance_number: int = -1
var intro_music_has_played: bool = false
var url: String
var click_mode: bool = false
var last_click_handled_time: int = 0
var shutdown_in_progress: bool = false

## Used to know if the client has ever connected before when performing a retry
var has_connected_once: bool = false
var connection_failed_message: String = "Connection Failed!"
# Text for use in game
var release_mouse_text: String = "ESC to Release Mouse"
var how_to_end_game_text: String = "END key to Close Game"
var exit_click_mode_text: String = "Press q to exit 'Click Mode' and control camera again."
var world_map: Node
var my_camera: Camera2D
var last_toast: String = ""
var initial_map_load_finished: bool = false
var resource_ids: Dictionary = {"Stone": 0, "Red Ore": 1}
var resource_names: Dictionary = {}
var has_built_resources_dictionary: bool = false
var players: Dictionary = {}


## Map Edges - A static variable defining the maximum map size
## Used by functions to find a safe place to place a player and to de-spawn objects that fall or fly out of the map.
class MapEdges:
	## Lowest x and y position of any possible occupied tile space
	class Min:
		static var x: int = -100000
		static var y: int = -100000

	## Highest x and y position of any possible occupied tile space
	class Max:
		static var x: int = 100000
		static var y: int = 100000


func get_resource_name(id: int) -> String:
	build_resources_dictionaries()
	return resource_names[id]


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
