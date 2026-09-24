class_name PlanetShape
extends RefCounted
## Natural terrain compositor: continents -> structural geology -> relief.
## The renderer and all downstream consumers sample this same final authority.
enum TerrainRegion { DEEP_OCEAN, SHALLOW_OCEAN, COAST, LOWLAND, PLATEAU, MOUNTAIN, ALPINE }
const REGION_NAMES := ["Oceano profundo","Oceano raso","Costa","Planície","Planalto","Montanha","Alpino"]
var definition: PlanetDefinition
var continental: ContinentalShape
var geology: PlanetGeology
var relief: TerrainRelief

func _init(source: PlanetDefinition, geology_context: PlanetGeology = null) -> void:
	definition=source
	geology=geology_context if geology_context else PlanetGeology.new(source)
	continental=geology._continental
	relief=TerrainRelief.new(source)

func sample_continental_components(direction: Vector3) -> Vector4:
	return continental.sample(direction)

func sample_components(direction: Vector3) -> Vector4:
	return relief.sample(direction,continental.sample(direction),geology)

func sample_height_m(direction: Vector3) -> float:
	return sample_components(direction).x


func sample_radius_m(direction: Vector3) -> float:
	return definition.radius_m + sample_height_m(direction)


func point_on_planet(direction: Vector3) -> Vector3:
	return direction.normalized() * sample_radius_m(direction)


func sample_normalized_height(direction: Vector3) -> float:
	return normalize_height(sample_height_m(direction))


func normalize_height(height_m: float) -> float:
	var height_range := definition.max_terrain_height_m + definition.ocean_depth_m
	if is_zero_approx(height_range):
		return 0.0
	return clampf((height_m - definition.sea_level_m + definition.ocean_depth_m) / height_range, 0.0, 1.0)


func classify_region(components: Vector4) -> TerrainRegion:
	var relative_height := components.x - definition.sea_level_m
	if relative_height < -definition.ocean_depth_m * 0.42:
		return TerrainRegion.DEEP_OCEAN
	if relative_height < -8.0:
		return TerrainRegion.SHALLOW_OCEAN
	if relative_height < 24.0 or components.y < 0.72:
		return TerrainRegion.COAST
	if relative_height > definition.max_terrain_height_m * 0.72:
		return TerrainRegion.ALPINE
	if components.z > 0.24:
		return TerrainRegion.MOUNTAIN
	if components.w > 0.42:
		return TerrainRegion.PLATEAU
	return TerrainRegion.LOWLAND


## Natural height authority. Future edits compose outside this function:
## final_height = sample_base_height(direction) + terrain_edit_delta(position_m).
## Mesh/collision stay rebuildable; edits must invalidate affected jobs by revision.
func sample_base_height(direction: Vector3) -> float:
	return sample_height_m(direction)
