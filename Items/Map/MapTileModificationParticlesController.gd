extends Node2D

const Width: int = 1000
const Height: int = 1000
var LocalImage: Image

var ParticleNodes = []
var ParticleNodeTime = []
var NodesTaken = []

var AllocatedNodes = 0
var InUseNodes = 0

@export var Map: TileMap
@export var ScaleCurve : Curve

func _process(delta):
	if(InUseNodes > 0):
		var Count = 0
		while(Count < len(ParticleNodes)):
			if(NodesTaken[Count]):
				ParticleNodeTime[Count] -= delta
				NodesTaken[Count] = ParticleNodeTime[Count]>0
				if(!NodesTaken[Count]):
					InUseNodes-=1
			Count+=1

var ParticleLifetime: float = 0.5
var ParticlesPerTile: int = 32


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
	
	return([Points,Colors])

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
	var TargetParticleNode : CPUParticles2D
	if(InUseNodes < AllocatedNodes):
		var Count = AllocatedNodes-1
		while(Count >= 0):
			if(!NodesTaken[Count]):
				TargetParticleNode = ParticleNodes[Count]
				NodesTaken[Count] = true
				ParticleNodeTime[Count] = ParticleLifetime
				break
			Count-=1
	else:
		TargetParticleNode = CPUParticles2D.new()
		add_child(TargetParticleNode)
		ParticleNodes.append(TargetParticleNode)
		ParticleNodeTime.append(ParticleLifetime)
		NodesTaken.append(true)
		AllocatedNodes+=1

	TargetParticleNode.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	TargetParticleNode.emission_points = Points
	TargetParticleNode.emission_colors = Colors
	TargetParticleNode.amount = Ammount
	TargetParticleNode.one_shot = true
	TargetParticleNode.emitting = true
	TargetParticleNode.explosiveness = 1
	TargetParticleNode.gravity = Vector2(0,980.0/2.0)
	TargetParticleNode.direction = Vector2(0,1)
	TargetParticleNode.spread = 45.0
	TargetParticleNode.initial_velocity_min = 0.1
	TargetParticleNode.initial_velocity_max = 20.0
	TargetParticleNode.scale_amount_curve = ScaleCurve
	#TargetParticleNode.restart()

	InUseNodes+=1
