extends CPUParticles2D

const Width: int = 1000
const Height: int = 1000
var LocalImage: Image

var Points: Array[Vector2]
var Colors: Array[Color]
var ParticleCount: int = 0
var Times: Array[bool]
var Blocks: Array[int]

@export var Map: TileMap


func _ready() -> void:
	emitting = ParticleCount > 0
	lifetime = ParticleLifetime
	if(ParticleCount > 0):
		amount = ParticleCount
	else:
		amount = 1
	pass

func _process(delta):
	if(len(Times) > 0):
		if(Times[0] == false):
			Times.remove_at(0)
			Points = Points.slice(0,len(Points)-Blocks[0])
			Colors = Colors.slice(0,len(Points)-Blocks[0])
			ParticleCount-=Blocks[0]*ParticlesPerTile
			Blocks.remove_at(0)

			emission_points = Points
			emission_colors = Colors
			if(ParticleCount > 0):
				amount = ParticleCount
			else:
				amount = 1
				emitting = false
		else:
			Times[0] = false
	pass
			
			

var ParticleLifetime: float = 1.0
var ParticlesPerTile: int = 16*16

func DestroyCellLocal(Position: Vector2i, ID: Vector2i) -> void:
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
		ParticleCount += ParticlesPerTile

func DestroyCells(Positions, IDs):
	var Count = len(Positions)-1
	while(Count >= 0):
		DestroyCellLocal(Positions[Count],IDs[Count])
		Count-=1

	Times.append(true)
	Blocks.append(len(Positions)*ParticlesPerTile)

	emission_points = Points
	emission_colors = Colors
	amount = ParticleCount
	emitting = true

func DestroyCell(Position, ID):
	DestroyCellLocal(Position,ID)

	Times.append(true)
	Blocks.append(ParticlesPerTile)

	emission_points = Points
	emission_colors = Colors
	amount = ParticleCount
	emitting = true