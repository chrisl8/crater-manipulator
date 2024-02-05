extends Node2D

const Width: int = 1000
const Height: int = 1000
var LocalImage: Image

var ParticleNodes: Array = []
var ParticleNodeTime: Array = []
var NodesTaken: Array = []

#Allocated particles are particle nodes that have been created and childed to this component, they are ALL the particles currently available
var AllocatedNodes: int = 0
#In use particles are particles that are currently emitting and have not been returned to the free pool
var InUseNodes: int = 0

@export var Map: TileMap
@export var ScaleCurve: Curve


func _process(delta: float) -> void:
	#Loop over nodes and return expired ones to the pool
	if InUseNodes > 0:
		var Count: int = 0
		while Count < len(ParticleNodes):
			if NodesTaken[Count]:
				#Node is taken, apply time
				ParticleNodeTime[Count] -= delta
				NodesTaken[Count] = ParticleNodeTime[Count] > 0
				if !NodesTaken[Count]:
					#Node is no longer taken, decrement in use count so allocator function knows to look for free allocated particles
					InUseNodes -= 1
			Count += 1


var ParticleLifetime: float = 0.5
var ParticlesPerTile: int = 32


#Calculate points and colors for single tile, repeat this for multiple tiles and combine results to create a block particle
func DestroyCellLocal(Position: Vector2i, ID: Vector2i) -> Array:
	var Points: Array = []
	var Colors: Array = []

	#Extract atlas image at tile, used for color sampling
	var Atlas: TileSetAtlasSource = Map.tile_set.get_source(0)
	var AtlasImage: Image = Atlas.texture.get_image()
	var TileImage: Image = AtlasImage.get_region(Atlas.get_tile_texture_region(ID))

	var PointsToSample: int = ParticlesPerTile
	var PointsSampled: Array = []
	while PointsToSample > 0:
		PointsToSample -= 1
		#TODO : Should store all possible points in variable on startup and pick randomly later, duplicates can be adressed or ignored
		#Current system checks if randomly generated value is duplicate and if so randomly picks again untill not so
		var SamplePosition: Vector2i = Vector2i(randi_range(0, 15), randi_range(0, 15))
		while SamplePosition in PointsSampled:
			SamplePosition = Vector2i(randi_range(0, 15), randi_range(0, 15))
		PointsSampled.append(SamplePosition)
		#Read pixel color, should not be expensive as image processing steps to this point 'should' be readonly
		var SampleColor: Color = TileImage.get_pixel(SamplePosition.x, SamplePosition.y)
		Points.append(
			Vector2(
				Position.x * 16.0 + SamplePosition.x + 0.5,
				Position.y * 16.0 + SamplePosition.y + 0.5
			)
		)

		Colors.append(SampleColor)

	return [Points, Colors]


#Collects tile data for each tile and combines into a single block particle
func DestroyCells(Positions: Array, IDs: Array) -> void:
	var Points: Array = []
	var Colors: Array = []
	var Amount: int = len(Positions) * ParticlesPerTile

	var Count: int = len(Positions) - 1
	while Count >= 0:
		var Output: Array = DestroyCellLocal(Positions[Count], IDs[Count])
		Points.append_array(Output[0])
		Colors.append_array(Output[1])
		Count -= 1

	AddParticalNodeFromProcessing(Points, Colors, Amount)


func DestroyCell(Position: Vector2i, ID: Vector2i) -> void:
	#This function is here for convenience
	DestroyCells([Position], [ID])


#Creates particle for given data
func AddParticalNodeFromProcessing(Points: Array, Colors: Array, Amount: int) -> void:
	var TargetParticleNode: CPUParticles2D
	if InUseNodes < AllocatedNodes:
		#If there are free allocated particles, select one
		var Count: int = AllocatedNodes - 1
		while Count >= 0:
			if !NodesTaken[Count]:
				TargetParticleNode = ParticleNodes[Count]
				NodesTaken[Count] = true
				ParticleNodeTime[Count] = ParticleLifetime
				break
			Count -= 1
	else:
		#If no allocated particles are free, create one and add it to the pool
		TargetParticleNode = CPUParticles2D.new()
		add_child(TargetParticleNode)
		ParticleNodes.append(TargetParticleNode)
		ParticleNodeTime.append(ParticleLifetime)
		NodesTaken.append(true)
		AllocatedNodes += 1

	#Configure particle system, some of this only needs to be performed on newly spawned particles
	TargetParticleNode.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	TargetParticleNode.emission_points = Points
	TargetParticleNode.emission_colors = Colors
	TargetParticleNode.amount = Amount
	TargetParticleNode.one_shot = true
	TargetParticleNode.emitting = true
	TargetParticleNode.explosiveness = 1
	TargetParticleNode.gravity = Vector2(0, 980.0 / 2.0)
	TargetParticleNode.direction = Vector2(0, 1)
	TargetParticleNode.spread = 45.0
	TargetParticleNode.initial_velocity_min = 0.1
	TargetParticleNode.initial_velocity_max = 20.0
	TargetParticleNode.scale_amount_curve = ScaleCurve
	#TargetParticleNode.restart()

	InUseNodes += 1
