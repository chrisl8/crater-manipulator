extends CPUParticles2D

const Width: int = 1000
const Height: int = 1000
var LocalImage: Image

var Points: Array[Vector2]
var Colors: Array[Color]
var ParticleCount = 0

@export var Map: TileMap


func _ready() -> void:
	#emitting = true
	pass

func DestroyCell(Position: Vector2i, ID: Vector2i) -> void:


	var Atlas: TileSetAtlasSource = Map.tile_set.get_source(0)
	var AtlasImage = Atlas.texture.get_image()
	var TileImage = AtlasImage.get_region(Atlas.get_tile_texture_region(ID))

	var PointsToSample = 1
	var PointsSampled = []
	while(PointsToSample > 0):
		PointsToSample-=1
		var SamplePosition = Vector2i(randi_range(0,15),randi_range(0,15))
		while(SamplePosition in PointsSampled):
			SamplePosition = Vector2i(randi_range(0,15),randi_range(0,15))
		PointsSampled.append(SamplePosition)
		var SampleColor = TileImage.get_pixel(SamplePosition.x,SamplePosition.y)
		Points.append(Vector2(Position.x*16.0 + SamplePosition.x+0.5,Position.y*16.0 + SamplePosition.y+0.5))
		Colors.append(SampleColor)
		ParticleCount+=1
		

	emission_points = Points
	emission_colors = Colors
	amount = ParticleCount
