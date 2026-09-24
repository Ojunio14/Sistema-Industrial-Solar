class_name PlanetBiomes
extends RefCounted
## Classificação superficial derivada: não fornece altura, geometria ou material.
enum Biome { TROPICAL_WET, SAVANNA, DESERT, SALAR, TEMPERATE, WETLAND,
	TAIGA, TUNDRA, ALPINE, POLAR }
const NAMES := ["Tropical úmido", "Savana", "Deserto", "Salar/deserto extremo",
	"Temperado", "Pântano/planície úmida", "Taiga", "Tundra", "Alpino", "Polar"]
const COLORS := [
	Color(0.04, 0.54, 0.27), Color(0.72, 0.66, 0.24), Color(0.91, 0.64, 0.30),
	Color(0.95, 0.80, 0.66), Color(0.32, 0.67, 0.37), Color(0.11, 0.52, 0.57),
	Color(0.15, 0.41, 0.39), Color(0.56, 0.64, 0.58), Color(0.60, 0.47, 0.65),
	Color(0.79, 0.87, 0.94)]

var _sea_level: float
var _shape: PlanetShape # Consulta direta apenas na main thread.
var _climate: PlanetClimate
var _basin_centers: Array[Vector3] = []
var _basin_radii := PackedFloat32Array()
var _basin_strengths := PackedFloat32Array()

func _init(definition: PlanetDefinition, climate: PlanetClimate, geology: PlanetGeology) -> void:
	_sea_level = definition.sea_level_m
	_shape = PlanetShape.new(definition.duplicate(true), geology)
	_climate = climate
	for descriptor in geology.descriptors():
		if int(descriptor.type) == PlanetGeology.Type.CLOSED_BASIN:
			_basin_centers.append(descriptor.center)
			_basin_radii.append(descriptor.radius)
			_basin_strengths.append(descriptor.strength)

func sample(direction: Vector3) -> PlanetBiomeSample:
	var output := PlanetBiomeSample.new()
	sample_into(direction, output)
	return output

func sample_position(local_position: Vector3) -> PlanetBiomeSample:
	return sample(local_position.normalized())

## Conveniência na main thread; o caminho quente recebe todos os contextos.
func sample_into(direction: Vector3, output: PlanetBiomeSample) -> void:
	var surface := _shape.sample_components(direction)
	var climate_sample := PlanetClimateSample.new()
	_climate.sample_with_surface_into(direction, surface, climate_sample)
	sample_with_context_into(direction, surface, climate_sample, output)

func _needs_basin(surface: Vector4, climate_sample: PlanetClimateSample) -> bool:
	var water := clampf(climate_sample.humidity * 0.55 +
		climate_sample.precipitation * 0.45 / 0.8, 0.0, 1.0)
	return surface.x > _sea_level and surface.x - _sea_level < 300.0 and \
		1.0 - water > 0.74

## Seguro em worker: arrays climáticos somente leitura, sem Node, RNG ou
## alocação de objeto. O caller mantém climate_sample/output exclusivos do job.
func sample_with_context_into(direction: Vector3, surface: Vector4,
		climate_sample: PlanetClimateSample, output: PlanetBiomeSample) -> void:
	var basin := _basin_influence(direction) if _needs_basin(surface, climate_sample) else 0.0
	classify_with_slope_into(direction, surface, climate_sample, basin,
		_climate.regional_slope(direction), output)

## Queda radial contínua dos descritores geológicos de bacia fechada; não usa
## o ID dominante, que pode mudar abruptamente na fronteira de províncias.
func _basin_influence(direction: Vector3) -> float:
	var d := direction.normalized()
	var influence := 0.0
	for i in range(_basin_centers.size()):
		var chord2 := 2.0 - 2.0 * clampf(d.dot(_basin_centers[i]), -1.0, 1.0)
		var radius2 := _basin_radii[i] * _basin_radii[i]
		if chord2 < radius2:
			var falloff := 1.0 - chord2 / radius2
			influence = maxf(influence, falloff * falloff * _basin_strengths[i])
	return clampf(influence, 0.0, 1.0)

## Núcleo testável com inclinação controlada. Valores locais contínuos geram
## pesos contínuos; somente os IDs dominantes são discretos.
func classify_with_slope_into(direction: Vector3, surface: Vector4,
		climate_sample: PlanetClimateSample, basin: float,
		regional_slope: float, output: PlanetBiomeSample) -> void:
	output.regional_slope = regional_slope
	var weights := output.weights
	if surface.x <= _sea_level:
		weights.fill(0.0)
		output.dominant = -1
		output.secondary = -1
		output.dominant_weight = 0.0
		output.secondary_weight = 0.0
		output.top_pair_mix = 0.5
		return
	var t := climate_sample.temperature_c
	var humidity := clampf(climate_sample.humidity, 0.0, 1.0)
	var rain := clampf(climate_sample.precipitation, 0.0, 1.0)
	var water := clampf(humidity * 0.55 + rain * 0.45 / 0.8, 0.0, 1.0)
	var dry := 1.0 - water
	var altitude := surface.x - _sea_level
	var latitude := absf(direction.normalized().y)
	var ocean := clampf(climate_sample.ocean_influence, 0.0, 1.0)
	var mountain := clampf(surface.z, 0.0, 1.0)
	var flat := 1.0 - smoothstep(0.025, 0.15, regional_slope)
	var lowland := 1.0 - smoothstep(90.0, 300.0, altitude)
	var alpine_context := smoothstep(320.0, 620.0, altitude) * \
		clampf(mountain * 1.5 + smoothstep(0.09, 0.25, regional_slope) * 0.45, 0.0, 1.0)
	weights[Biome.TROPICAL_WET] = 1.35 * _bell(t, 27.0, 13.0) * _bell(water, 0.84, 0.27)
	weights[Biome.SAVANNA] = 1.05 * _bell(t, 25.0, 16.0) * _bell(water, 0.48, 0.24)
	weights[Biome.DESERT] = 1.15 * _bell(t, 19.0, 27.0) * smoothstep(0.40, 0.78, dry)
	weights[Biome.SALAR] = 1.35 * _bell(t, 19.0, 26.0) * smoothstep(0.74, 0.94, dry) * \
		lowland * flat * (0.28 + 2.2 * basin)
	weights[Biome.TEMPERATE] = 1.15 * _bell(t, 11.0, 17.0) * _bell(water, 0.58, 0.40)
	weights[Biome.WETLAND] = 1.8 * _bell(t, 18.0, 18.0) * smoothstep(0.57, 0.83, water) * \
		lowland * flat * (0.60 + 0.40 * ocean)
	weights[Biome.TAIGA] = 1.20 * _bell(t, -5.0, 11.0) * _bell(water, 0.51, 0.40) * \
		(0.78 + 0.22 * (1.0 - ocean))
	weights[Biome.TUNDRA] = 1.12 * _bell(t, -16.0, 11.0) * (1.0 - 0.12 * water) * \
		(1.0 - 0.60 * alpine_context)
	weights[Biome.ALPINE] = 2.20 * _bell(t, -7.0, 21.0) * alpine_context * \
		(1.0 - smoothstep(0.78, 0.97, latitude))
	weights[Biome.POLAR] = 1.90 * _bell(t, -27.0, 11.0) * smoothstep(0.57, 0.86, latitude)
	var total := 0.0
	var first := -1
	var second := -1
	var best := -1.0
	var runner_up := -1.0
	for i in range(weights.size()):
		var score := weights[i]
		total += score
		if score > best:
			runner_up = best
			second = first
			best = score
			first = i
		elif score > runner_up:
			runner_up = score
			second = i
	var inv_total := 1.0 / maxf(total, 0.0000001)
	for i in range(weights.size()):
		weights[i] *= inv_total
	output.dominant = first
	output.secondary = second
	output.dominant_weight = best * inv_total
	output.secondary_weight = runner_up * inv_total
	output.top_pair_mix = best / maxf(best + runner_up, 0.0000001)

static func _bell(value: float, center: float, width: float) -> float:
	var x := (value - center) / width
	return exp(-x * x)

## F7 cria estas texturas sob demanda. A classificação exata permanece na API.
func create_debug_textures() -> Array[Texture2D]:
	var width := PlanetClimate.WIDTH
	var height := PlanetClimate.HEIGHT
	var categorical := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var blending := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var climate_sample := PlanetClimateSample.new()
	var biome_sample := PlanetBiomeSample.new()
	for y in range(height):
		for x in range(width):
			var i := x + y * width
			var d := PlanetClimate._grid_direction(x, y)
			var surface := Vector4(_climate._heights[i] + _sea_level,
				_climate._land[i], _climate._mountains[i], 0.0)
			_climate.sample_with_surface_into(d, surface, climate_sample)
			sample_with_context_into(d, surface, climate_sample, biome_sample)
			var id := biome_sample.dominant
			var dominant_color: Color = COLORS[id] if id >= 0 else Color(0.08, 0.25, 0.45)
			var blended := Color(0.08, 0.25, 0.45)
			if id >= 0:
				blended = Color.BLACK
				for b in range(10):
					blended += COLORS[b] * biome_sample.weights[b]
			categorical.set_pixel(x, y, Color(dominant_color.r, dominant_color.g,
				dominant_color.b, biome_sample.dominant_weight))
			blending.set_pixel(x, y, Color(blended.r, blended.g, blended.b, 1.0))
	return [ImageTexture.create_from_image(categorical),
		ImageTexture.create_from_image(blending)]
