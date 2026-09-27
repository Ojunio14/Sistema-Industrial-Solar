class_name PlanetMaterialWeights
extends RefCounted
## Aparência derivada. Os serviços de terreno, geologia, clima e biomas seguem como autoridades.
enum Family { ROCK_GENERIC, ROCK_SEDIMENTARY, ROCK_VOLCANIC, SOIL, SAND, ARID_GROUND, SNOW_ICE, GRAVEL }
const NAMES := ["rock_generic", "rock_sedimentary", "rock_volcanic", "soil", "sand", "arid_ground", "snow_ice", "gravel"]

var _geology: PlanetGeology
var _sea_level: float

func _init(definition: PlanetDefinition, geology: PlanetGeology) -> void:
	_sea_level = definition.sea_level_m
	_geology = geology

## Pesos contínuos, em ordem NAMES; água devolve oito zeros. O caller reutiliza output.
func sample_into(direction: Vector3, surface: Vector4, normal: Vector3,
		climate: PlanetClimateSample, biome: PlanetBiomeSample,
		output: PackedFloat32Array) -> void:
	assert(output.size() == 8)
	output.fill(0.0)
	if surface.x <= _sea_level or biome.is_water():
		return
	var slope := clampf(1.0 - normal.normalized().dot(direction.normalized()), 0.0, 1.0)
	var rock := smoothstep(0.035, 0.36, slope)
	var steep := smoothstep(0.10, 0.48, slope)
	var flat := 1.0 - smoothstep(0.025, 0.22, slope)
	var w := biome.weights
	var tropical: float = w[PlanetBiomes.Biome.TROPICAL_WET]
	var savanna: float = w[PlanetBiomes.Biome.SAVANNA]
	var desert: float = w[PlanetBiomes.Biome.DESERT]
	var salar: float = w[PlanetBiomes.Biome.SALAR]
	var temperate: float = w[PlanetBiomes.Biome.TEMPERATE]
	var wetland: float = w[PlanetBiomes.Biome.WETLAND]
	var taiga: float = w[PlanetBiomes.Biome.TAIGA]
	var tundra: float = w[PlanetBiomes.Biome.TUNDRA]
	var alpine: float = w[PlanetBiomes.Biome.ALPINE]
	var polar: float = w[PlanetBiomes.Biome.POLAR]
	var dry := clampf(1.0 - climate.humidity, 0.0, 1.0)
	var altitude := climate.altitude_m
	# Base costeira contínua; a macrovariação de areia/cascalho ocorre no shader.
	var coast := (1.0 - smoothstep(7.0, 100.0, altitude)) * flat * \
		clampf(climate.ocean_influence * 0.7 + dry * 0.3, 0.0, 1.0)
	var cold := 1.0 - smoothstep(-10.0, 6.0, climate.temperature_c)
	var high_cold := smoothstep(320.0, 850.0, altitude) * \
		(1.0 - smoothstep(-1.0, 12.0, climate.temperature_c))
	var snow := clampf(maxf(cold * (0.35 + 0.65 * polar),
		high_cold * (0.5 + 0.5 * alpine)) + 0.4 * tundra, 0.0, 1.0) * \
		(1.0 - 0.82 * steep)
	# A influência das províncias vem dos falloffs contínuos, não do ID dominante.
	var igneous := 0.0
	var sediment := 0.0
	for province: PlanetGeology.Province in _geology.relief_candidates(direction):
		if province.kind != PlanetGeology.Type.IGNEOUS and \
			province.kind != PlanetGeology.Type.SEDIMENTARY and \
			province.kind != PlanetGeology.Type.FORMER_MARINE:
			continue
		var chord2 := 2.0 - 2.0 * clampf(direction.dot(province.center), -1.0, 1.0)
		var radius2: float = province.radius * province.radius
		if chord2 >= radius2:
			continue
		var falloff := 1.0 - chord2 / radius2
		var influence: float = falloff * falloff * province.strength
		if province.kind == PlanetGeology.Type.IGNEOUS:
			igneous = maxf(igneous, influence)
		else:
			sediment = maxf(sediment, influence)
	var land_stability := 1.0 - 0.78 * rock
	output[Family.ROCK_GENERIC] = 0.10 + 1.65 * rock + surface.z * 0.35
	output[Family.ROCK_SEDIMENTARY] = 0.07 + 0.85 * sediment * (0.35 + 0.65 * rock) + 0.18 * surface.w
	output[Family.ROCK_VOLCANIC] = 0.04 + 1.65 * igneous * (0.45 + 0.55 * rock)
	output[Family.SOIL] = (0.18 + 1.35 * (tropical + temperate + wetland + taiga) + \
		0.55 * savanna) * land_stability * (1.0 - 0.55 * snow)
	output[Family.SAND] = 0.02 + 2.20 * coast + (0.72 * desert + 0.40 * salar) * flat
	output[Family.ARID_GROUND] = 0.04 + (1.55 * desert + 1.35 * salar + 0.65 * savanna) * \
		(0.30 + 0.70 * dry) * land_stability
	output[Family.SNOW_ICE] = 0.02 + 2.8 * snow
	output[Family.GRAVEL] = 0.05 + 0.75 * rock * (1.0 - 0.5 * steep) + \
		0.28 * (tundra + alpine) + 0.12 * sediment
	var total := 0.0
	for value in output:
		total += value
	for i in range(8):
		output[i] /= maxf(total, 0.000001)

static func top_three(weights: PackedFloat32Array) -> Vector3i:
	var ids := Vector3i(-1, -1, -1)
	for i in range(8):
		if weights[i] > (weights[ids.x] if ids.x >= 0 else -1.0):
			ids = Vector3i(i, ids.x, ids.y)
		elif weights[i] > (weights[ids.y] if ids.y >= 0 else -1.0):
			ids = Vector3i(ids.x, i, ids.y)
		elif weights[i] > (weights[ids.z] if ids.z >= 0 else -1.0):
			ids.z = i
	return ids
