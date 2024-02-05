extends Node2D

const WIDTH: int = 1000
const HEIGHT: int = 1000

@export var map: TileMap
@export var scale_curve: Curve

var local_image: Image
var particle_nodes: Array = []
var particle_node_time: Array = []
var nodes_taken: Array = []
#Allocated particles are particle nodes that have been created and childed to this component, they are ALL the particles currently available
var allocated_nodes: int = 0
#In use particles are particles that are currently emitting and have not been returned to the free pool
var in_use_nodes: int = 0
var particle_lifetime: float = 0.5
var particles_per_tile: int = 32


func _process(delta: float) -> void:
	#Loop over nodes and return expired ones to the pool
	if in_use_nodes > 0:
		var count: int = 0
		while count < len(particle_nodes):
			if nodes_taken[count]:
				particle_node_time[count] -= delta
				nodes_taken[count] = particle_node_time[count] > 0
				if !nodes_taken[count]:
					#Node is no longer taken, decrement in use count so allocator function knows to look for free allocated particles
					in_use_nodes -= 1
			count += 1


#Calculate points and colors for single tile, repeat this for multiple tiles and combine results to create a block particle
func destroy_cell_local(at_position: Vector2i, id: Vector2i) -> Array:
	print("destroy_cell_local ", at_position, " ", id)
	var points: Array = []
	var colors: Array = []

	#Extract atlas image at tile, used for color sampling
	var atlas: TileSetAtlasSource = map.tile_set.get_source(0)
	var atlas_image: Image = atlas.texture.get_image()
	var tile_image: Image = atlas_image.get_region(atlas.get_tile_texture_region(id))

	var points_to_sample: int = particles_per_tile
	var points_sampled: Array = []
	while points_to_sample > 0:
		points_to_sample -= 1
		#TODO : Should store all possible points in variable on startup and pick randomly later, duplicates can be addressed or ignored
		#Current system checks if randomly generated value is duplicate and if so randomly picks again until not so
		var sample_position: Vector2i = Vector2i(randi_range(0, 15), randi_range(0, 15))
		while sample_position in points_sampled:
			sample_position = Vector2i(randi_range(0, 15), randi_range(0, 15))
		points_sampled.append(sample_position)
		#Read pixel color, should not be expensive as image processing steps to this point 'should' be readonly
		var sample_color: Color = tile_image.get_pixel(sample_position.x, sample_position.y)
		points.append(
			Vector2(
				at_position.x * 16.0 + sample_position.x + 0.5,
				at_position.y * 16.0 + sample_position.y + 0.5
			)
		)

		colors.append(sample_color)

	return [points, colors]


## Collects tile data for each tile and combines into a single block particle
func destroy_cells(positions: Array, ids: Array) -> void:
	Helpers.log_print(str("destroy_cells ", positions, " ", ids))
	var points: Array = []
	var colors: Array = []
	var amount: int = len(positions) * particles_per_tile

	var count: int = len(positions) - 1
	while count >= 0:
		var output: Array = destroy_cell_local(positions[count], ids[count])
		points.append_array(output[0])
		colors.append_array(output[1])
		count -= 1

	add_particle_node_from_processing(points, colors, amount)


## Convenience function to destroy a single cell
## It just puts your arguments into arrays and calls destroy_cells()
func destroy_cell(at_position: Vector2i, id: Vector2i) -> void:
	destroy_cells([at_position], [id])


## Creates particle for given data
func add_particle_node_from_processing(points: Array, colors: Array, amount: int) -> void:
	var target_particle_node: CPUParticles2D
	if in_use_nodes < allocated_nodes:
		#If there are free allocated particles, select one
		var count: int = allocated_nodes - 1
		while count >= 0:
			if !nodes_taken[count]:
				target_particle_node = particle_nodes[count]
				nodes_taken[count] = true
				particle_node_time[count] = particle_lifetime
				break
			count -= 1
	else:
		#If no allocated particles are free, create one and add it to the pool
		target_particle_node = CPUParticles2D.new()
		add_child(target_particle_node)
		particle_nodes.append(target_particle_node)
		particle_node_time.append(particle_lifetime)
		nodes_taken.append(true)
		allocated_nodes += 1

	#Configure particle system, some of this only needs to be performed on newly spawned particles
	target_particle_node.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	target_particle_node.emission_points = points
	target_particle_node.emission_colors = colors
	target_particle_node.amount = amount
	target_particle_node.one_shot = true
	target_particle_node.emitting = true
	target_particle_node.explosiveness = 1
	target_particle_node.gravity = Vector2(0, 980.0 / 2.0)
	target_particle_node.direction = Vector2(0, 1)
	target_particle_node.spread = 45.0
	target_particle_node.initial_velocity_min = 0.1
	target_particle_node.initial_velocity_max = 20.0
	target_particle_node.scale_amount_curve = scale_curve
	#TargetParticleNode.restart()

	in_use_nodes += 1
