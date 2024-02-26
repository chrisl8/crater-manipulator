extends Node2D

const MAX_STONE: int = 100
const MAX_BAR_SCALE: float = 4

@export var stone_bar: Control

var powder_resources: Dictionary = {}
var is_local: bool = false
var inventory_updated: bool = false


func _ready() -> void:
	#Round about because names dictionary isn't defined till request
	for key: String in Globals.resource_ids.keys():
		powder_resources[key] = 0


func initialize(new_is_local: bool) -> void:
	is_local = new_is_local
	set_process(is_local)
	inventory_updated = true


func _process(_delta: float) -> void:
	if inventory_updated:
		stone_bar.scale.y = (
			float(MAX_BAR_SCALE) / float(MAX_STONE) * float(powder_resources["Stone"])
		)
		#print(float(MAX_BAR_SCALE) / float(MAX_STONE) * float(powder_resources["Stone"]))
		#print(stone_bar.scale.y)
		inventory_updated = false


#func AddResource(ID: Vector2i, Amount: int):
#	if ID.x == 0:
#		pass


func add_data(data: Dictionary) -> void:
	for key: int in data.keys():
		var resource_name: String = Globals.get_resource_name(key)
		if powder_resources.has(resource_name):
			var extra: int = powder_resources[resource_name] + data[key] - MAX_STONE
			if extra <= 0:
				powder_resources[resource_name] += data[key]
			else:
				#Too much stone, delete extra for now
				powder_resources[resource_name] = MAX_STONE
	inventory_updated = true
