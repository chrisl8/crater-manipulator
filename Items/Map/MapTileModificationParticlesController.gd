extends Node2D

const Width: int = 1000
const Height: int = 1000
var LocalImage: Image

var ParticleNodes = []
var AllocatedNodes = 0
var InUseNodes = 0

@export var Map: TileMap

var SpawnedParticleNodes = []

func _process(delta):
	if(len(Times) > 0):
		for Emitter in EmissionFlags:
			Emitter.emitting = false
		EmissionFlags.clear()
		Times[0]-=delta
		if(Times[0] <= 0):
			if(len(Times) > 1):
				Times[1]+=Times[0]
			Times.remove_at(0)
			Points = Points.slice(0,len(Points)-Blocks[0])
			Colors = Colors.slice(0,len(Points)-Blocks[0])
			ParticleCount-=Blocks[0]*ParticlesPerTile

			while(Blocks[0] > 0):
				Blocks[0]-=1
				SpawnedParticleNodes[0].queue_free()

			SpawnedParticleNodes = SpawnedParticleNodes.slice(0,len(Points)-Blocks[0])

			Blocks.remove_at(0)
	pass


var ParticleLifetime: float = 1.0
var ParticlesPerTile: int = 16 * 16


func DestroyCellLocal(Position: Vector2i, ID: Vector2i):
	var Points = []
	var Colors = []

	var Atlas: TileSetAtlasSource = Map.tile_set.get_source(0)
	var AtlasImage: Image = Atlas.texture.get_image()
	var TileImage: Image = AtlasImage.get_region(Atlas.get_tile_texture_region(ID))

	var PointsToSample: int = ParticlesPerTile
	var PointsSampled: Array = []
	while PointsToSample > 0:
		PointsToSample -= 1
		#Should store all possible points in variable on startup and pick randomly later, duplicates can be adressed or ignored
		var SamplePosition: Vector2i = Vector2i(randi_range(0, 15), randi_range(0, 15))
		while SamplePosition in PointsSampled:
			SamplePosition = Vector2i(randi_range(0, 15), randi_range(0, 15))
		PointsSampled.append(SamplePosition)
		var SampleColor: Color = TileImage.get_pixel(SamplePosition.x, SamplePosition.y)
		Points.append(
			Vector2(
				Position.x * 16.0 + SamplePosition.x + 0.5,
				Position.y * 16.0 + SamplePosition.y + 0.5
			)
		)
		Colors.append(SampleColor)

	return([PointsSampled,Colors])

func DestroyCells(Positions, IDs):
	var Points = []
	var Colors = []
	var Ammount = len(Positions)*ParticlesPerTile

	var Count = len(Positions)-1
	while(Count >= 0):
		var Output = DestroyCellLocal(Positions[Count],IDs[Count])
		Points.append_array(Output[0])
		Colors.append_array(Output[1])
		Count-=1

	AddParticalNodeFromProcessing(Points,Colors,Ammount)
	
	

func DestroyCell(Position, ID):
	DestroyCells([Position],[ID])

	

func AddParticalNodeFromProcessing(Points, Colors, Ammount):
	#if(AllocatedNodes < InUseNodes):
	#	InUseNodes+=1
	#else:

	var NewParticles = CPUParticles2D.new()
	add_child(NewParticles)
	NewParticles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	NewParticles.emission_points = Points
	NewParticles.emission_colors = Colors
	NewParticles.amount = Ammount
	NewParticles.one_shot = true
	NewParticles.restart()

	SpawnedParticleNodes.append(NewParticles)
