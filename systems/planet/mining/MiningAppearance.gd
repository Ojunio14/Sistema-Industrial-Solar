class_name MiningAppearance
extends RefCounted
## One context per worker, not per cell. Same Stage 11 service and attributes.
var shape: PlanetShape
var climate: PlanetClimate
var biomes: PlanetBiomes
var selector: PlanetMaterialWeights
var weather := PlanetClimateSample.new()
var habitat := PlanetBiomeSample.new()
var weights := PackedFloat32Array()

func _init(natural: PlanetShape, climate_source: PlanetClimate, biome_source: PlanetBiomes) -> void:
	shape = natural
	climate = climate_source
	biomes = biome_source
	selector = PlanetMaterialWeights.new(shape.definition, shape.geology)
	weights.resize(8)

func sample(d: Vector3, surface: Vector4, normal: Vector3) -> Dictionary:
	var context := shape.geology.sample_with_surface(d, surface)
	weights.fill(0)
	if climate and biomes:
		climate.sample_with_surface_into(d, surface, weather)
		biomes.sample_with_context_into(d, surface, weather, habitat)
		selector.sample_into(d, surface, normal, weather, habitat, weights)
	return {"c": Color(shape.normalize_height(surface.x), surface.y, surface.z, surface.w),
		"g": context, "a": Vector4(weights[0], weights[1], weights[2], weights[3]),
		"b": Vector4(weights[4], weights[5], weights[6], weights[7])}
