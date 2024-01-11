extends Node2D


var PowderResources: Dictionary = {}


# Called when the node enters the scene tree for the first time.
func _ready():
	#Round about because names dictionary isn't defined till request
	for Key in Globals.ResourceIDs.keys():
		PowderResources[Key] = 0


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	#print(PowderResources["Stone"])
	pass



func AddResource(ID: Vector2i, Ammount: int):
	if(ID.x == 0):
		pass

func AddData(Data) -> void:

	for Key in Data.keys():
		PowderResources[Globals.GetResourceName(Key)] += Data[Key]