extends Node

var server_config: Dictionary = {}
var server_player_save_data_file_name: String = "user://server_player_data.dat"
var player_save_data: Dictionary = {}
var is_server: bool = false
var force_client: bool = false
var shutdown_server: bool = false
var user_name: String = ""
var local_debug_instance_number: int = -1
var intro_music_has_played: bool = false
var url: String
var click_mode: bool = false
var last_click_handled_time: int = 0
var shutdown_in_progress: bool = false

var connection_failed_message: String = "Connection Failed!"

# Text for use in game
var release_mouse_text: String = "ESC to Release Mouse"
var how_to_end_game_text: String = "END key to Close Game"
var exit_click_mode_text: String = "Press q to exit 'Click Mode' and control camera again."
var WorldMap: Node

var my_camera: Camera2D
var last_toast: String = ""

var initial_map_load_finished: bool = false

#Resources
var ResourceIDs = {"Stone": 0, "Red Ore": 1}
var ResourceNames = {}


func GetResourceName(ID):
	BuildResourcesDictionaries()
	return ResourceNames[ID]


func GetResourceID(Name):
	BuildResourcesDictionaries()
	return ResourceIDs[Name]


var HasBuiltResourcesDistionary = false


func BuildResourcesDictionaries():
	if !HasBuiltResourcesDistionary:
		for Key in ResourceIDs.keys():
			ResourceNames[ResourceIDs[Key]] = Key
		HasBuiltResourcesDistionary = true


var Players = {}
