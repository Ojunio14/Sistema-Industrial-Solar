class_name PlanetSurfaceSelection
extends RefCounted
## Surface appearance inputs only. Terrain/geology/climate remain the authorities.
## x volcanic, y sedimentary, z dry-biome affinity, all 0..1.
static func factors(geology: Vector4, climate: PlanetClimateSample) -> Vector3:
	var kind := PlanetGeology.type_of(int(geology.x))
	var strength := clampf(geology.z, 0.0, 1.0)
	var volcanic := strength if kind == PlanetGeology.Type.IGNEOUS else 0.0
	var sedimentary := strength if kind == PlanetGeology.Type.SEDIMENTARY or kind == PlanetGeology.Type.FORMER_MARINE else 0.0
	var dry := climate.weights[PlanetClimate.Biome.SAVANNA] + climate.weights[PlanetClimate.Biome.DESERT] + climate.weights[PlanetClimate.Biome.SALAR]
	return Vector3(volcanic, sedimentary, clampf(dry, 0.0, 1.0))

static func slope(normal: Vector3, radial: Vector3) -> float:
	return 1.0 - clampf(normal.dot(radial), 0.0, 1.0)

static func rock_exposure(slope_value: float) -> float:
	return smoothstep(0.08, 0.52, slope_value)

## Oracle for shader's eight continuous base weights; meso perturbation is visual only.
static func weights(altitude: float, slope_value: float, coast: float,
		temperature: float, humidity: float, precipitation: float,
		factors_value: Vector3) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(PlanetMaterialLibrary.FAMILIES.size())
	if altitude <= 0.0:
		return result
	var exposed := rock_exposure(slope_value)
	var flat := 1.0 - exposed
	var dry_heat := smoothstep(5.0, 25.0, temperature)
	var cold := 1.0 - smoothstep(-10.0, 1.0, temperature)
	var snow := cold * 3.0 * (1.0 - 0.72 * exposed)
	var shore := clampf(coast, 0.0, 1.0) * (1.0 - smoothstep(10.0, 95.0, altitude)) * flat
	result[PlanetMaterialLibrary.Family.ROCK_GENERIC] = 0.14 + 1.8 * exposed * exposed
	result[PlanetMaterialLibrary.Family.ROCK_SEDIMENTARY] = factors_value.y * (1.0 + exposed) * 1.7
	result[PlanetMaterialLibrary.Family.ROCK_VOLCANIC] = factors_value.x * (1.0 + exposed) * 2.1
	result[PlanetMaterialLibrary.Family.SOIL] = (0.25 + 0.85 * humidity) * flat * (1.0 - 0.8 * cold)
	result[PlanetMaterialLibrary.Family.SAND] = 1.8 * shore + 0.45 * factors_value.z * dry_heat * flat
	result[PlanetMaterialLibrary.Family.ARID_GROUND] = (1.0 - precipitation) * (0.3 + 0.7 * dry_heat) * (0.35 + 0.65 * factors_value.z) * flat * 1.7
	result[PlanetMaterialLibrary.Family.SNOW_ICE] = snow
	result[PlanetMaterialLibrary.Family.GRAVEL] = 0.10 + 3.0 * exposed * flat
	var total := 0.0
	for value in result:
		total += value
	for i in range(result.size()):
		result[i] /= total
	return result
