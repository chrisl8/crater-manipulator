extends Node2D

var PowderResources: Dictionary = {}

@export var StoneBar : Control
const MaxStone: int = 100
const MaxBarScale: float = 4

# Called when the node enters the scene tree for the first time.
func _ready():
	#Round about because names dictionary isn't defined till request
	for Key in Globals.ResourceIDs.keys():
		PowderResources[Key] = 0

var IsLocal: bool = false
func Initialize(NewIsLocal):
	IsLocal = NewIsLocal
	set_process(IsLocal)
	InventoryUpdated = true

var InventoryUpdated: bool = false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if(InventoryUpdated):
		StoneBar.scale.y  = float(MaxBarScale) / float(MaxStone) * float(PowderResources["Stone"])
		print(float(MaxBarScale) / float(MaxStone) * float(PowderResources["Stone"]))
		print(StoneBar.scale.y)
		InventoryUpdated = false



#func AddResource(ID: Vector2i, Ammount: int):
#	if ID.x == 0:
#		pass


func AddData(Data) -> void:
	for Key in Data.keys():
		var Extra = PowderResources[Globals.GetResourceName(Key)]+Data[Key] - MaxStone
		if(Extra <= 0):
			PowderResources[Globals.GetResourceName(Key)] += Data[Key]
		else:
			#Too much stone, delete extra for now
			PowderResources[Globals.GetResourceName(Key)] = MaxStone
	InventoryUpdated = true
