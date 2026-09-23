class_name PlanetClimate
extends RefCounted
## Static surface climate. Terrain is read-only and remains the height authority.
## Directions are planet-local unit vectors; no face/LOD/camera/query-order state.
const SEED_SALT := 0x434C494D # CLIM
const LAPSE_C_PER_M := 0.009
const BINS := 8

enum Biome { TROPICAL_WET, SAVANNA, DESERT, SALAR, TEMPERATE, WETLAND,
	TAIGA, TUNDRA, ALPINE, POLAR }
const BIOME_NAMES := ["Tropical wet", "Savanna", "Desert", "Salar/extreme desert",
	"Temperate", "Wetland", "Taiga", "Tundra", "Alpine", "Polar"]

class Belt:
	extends RefCounted
	var center: Vector3
	var u: Vector3
	var v: Vector3
	var length: float
	var width: float
	var strength: float

var _terrain: PlanetTerrain
var _seed: int
var _phase: float
var _belts: Array[Belt] = []
var _buckets: Array[Array] = []
var _basins := PackedVector4Array() # xyz center, w conservative inner radius

func _init(seed_value: int, terrain: PlanetTerrain) -> void:
	assert(terrain != null)
	_seed = seed_value
	_terrain = terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ SEED_SALT
	_phase = rng.randf_range(-PI, PI)
	for source in terrain.structural_blueprint():
		if source.kind != PlanetTerrain.Form.CHAIN and source.kind != PlanetTerrain.Form.RANGE:
			continue
		var belt := Belt.new()
		belt.center = source.center
		belt.u = source.u
		belt.v = source.v
		belt.length = source.length
		belt.width = source.width
		belt.strength = clampf(source.amplitude / 1300.0, 0.25, 1.0)
		_belts.append(belt)
	if terrain.geology != null:
		for descriptor in terrain.geology.descriptors():
			if descriptor.type == PlanetGeology.Type.CLOSED_BASIN:
				var d: Vector3 = descriptor.direction
				_basins.append(Vector4(d.x, d.y, d.z, minf(descriptor.length, descriptor.width)))
	_build_index()

func _build_index() -> void:
	for z in range(BINS):
		for y in range(BINS):
			for x in range(BINS):
				var center := (Vector3(x, y, z) + Vector3.ONE * 0.5) * (2.0 / BINS) - Vector3.ONE
				var selected: Array[Belt] = []
				for belt in _belts:
					var support := maxf(belt.length * 1.5, belt.width * 3.0)
					var chord := sqrt(2.0 - 2.0 * sqrt(1.0 - support * support))
					if center.distance_to(belt.center) <= chord + sqrt(3.0) / BINS + 0.00001:
						selected.append(belt)
				_buckets.append(selected)

func get_seed() -> int:
	return _seed

func query_position(position: Vector3) -> PlanetClimateSample:
	assert(position.is_finite() and not position.is_zero_approx())
	return query_direction(position.normalized())

func query_direction(d: Vector3) -> PlanetClimateSample:
	var result := PlanetClimateSample.new()
	var terrain_fields := _terrain.sample_fields(d)
	sample_into(d, terrain_fields, result)
	return result

static func temperature_at(abs_sin_latitude: float, altitude_m: float, ocean_influence: float) -> float:
	var base := 30.0 - 56.0 * pow(clampf(abs_sin_latitude, 0.0, 1.0), 1.2)
	return lerpf(base, 16.0 + (base - 16.0) * 0.75, clampf(ocean_influence, 0.0, 1.0) * 0.75) \
		- maxf(0.0, altitude_m) * LAPSE_C_PER_M

static func ocean_influence(continentality: float) -> float:
	return 1.0 - smoothstep(0.01, 0.30, continentality)

## Called with the already-authoritative terrain sample in the hot mesh loop.
## Reuses output and its ten weights, never constructs per-query descriptors/RNG.
func sample_into(d: Vector3, surface: Vector4, output: PlanetClimateSample) -> void:
	var latitude := absf(d.y)
	var ocean := ocean_influence(surface.y)
	var temperature := temperature_at(latitude, surface.x, ocean)
	var wind_sign := -1.0 + 2.0 * smoothstep(0.35, 0.50, latitude) - 2.0 * smoothstep(0.78, 0.88, latitude)
	var east := Vector3.UP.cross(d)
	if east.length_squared() > 0.00000001:
		east = east.normalized()
	else:
		east = Vector3.RIGHT
	var poleward := Vector3.UP - d * d.y
	if poleward.length_squared() > 0.00000001:
		poleward = poleward.normalized()
	else:
		poleward = Vector3.FORWARD
	var wind := (east * wind_sign - poleward * (0.3 * d.y)).normalized()
	var shadow := 0.0
	var windward := 0.0
	var rugged := 0.0
	for belt: Belt in _buckets[PlanetTerrain._bucket(d)]:
		var x := d.dot(belt.u) / belt.length
		var y := d.dot(belt.v) / belt.width
		var along := 1.0 - smoothstep(0.85, 1.5, absf(x))
		if along <= 0.0 or absf(y) >= 3.0:
			continue
		var crosswind := wind.dot(belt.v)
		var transport := smoothstep(0.12, 0.55, absf(crosswind)) * (1.0 - smoothstep(0.94, 1.0, latitude))
		var lee := y * signf(crosswind)
		var influence := belt.strength * along * transport
		shadow = maxf(shadow, influence * smoothstep(-0.1, 0.65, lee) * (1.0 - smoothstep(1.5, 3.0, lee)))
		windward = maxf(windward, influence * smoothstep(-2.5, -0.4, lee) * (1.0 - smoothstep(-0.1, 0.5, lee)))
		rugged = maxf(rugged, along * (1.0 - smoothstep(0.7, 2.2, absf(y))))
	var basin := 0.0
	for cap in _basins:
		var center := Vector3(cap.x, cap.y, cap.z)
		basin = maxf(basin, 1.0 - smoothstep(0.25, 1.0, d.distance_to(center) / cap.w))
	var wet_belt := 0.30 + 0.43 * exp(-pow(latitude / 0.27, 2.0)) \
		+ 0.22 * exp(-pow((latitude - 0.70) / 0.16, 2.0)) \
		- 0.27 * exp(-pow((latitude - 0.42) / 0.14, 2.0)) - 0.12 * smoothstep(0.78, 1.0, latitude)
	var regional := 0.10 * sin(d.x * 5.0 + _phase) * cos(d.z * 4.0 - d.y * 2.0)
	var humidity := clampf(wet_belt + 0.28 * ocean + regional + 0.14 * windward - 0.42 * shadow - 0.12 * basin, 0.0, 1.0)
	var rain := clampf(humidity * (0.77 + 0.13 * (1.0 - latitude) + 0.10 * windward) - 0.10 * shadow, 0.0, 1.0)
	output.climate = Vector4(temperature, humidity, ocean, rain)
	output.rain_shadow = shadow
	_classify(output, surface.x, latitude, rugged, basin)

static func _bell(value: float, center: float, width: float) -> float:
	var t := (value - center) / width
	return exp(-t * t)

func _classify(output: PlanetClimateSample, altitude: float, latitude: float, rugged: float, basin: float) -> void:
	var weights := output.weights
	if altitude <= 0.0:
		weights.fill(0.0)
		output.dominant = -1
		output.secondary = -1
		output.top_pair_mix = 1.0
		return
	var t := output.climate.x
	var p := output.climate.w
	var ocean := output.climate.z
	var desert := _bell(t, 27.0, 17.0) * _bell(p, 0.16, 0.22)
	var lowland := 1.0 - smoothstep(80.0, 330.0, altitude)
	weights[Biome.TROPICAL_WET] = _bell(t, 29.0, 12.0) * _bell(p, 0.84, 0.27)
	weights[Biome.SAVANNA] = _bell(t, 27.0, 14.0) * _bell(p, 0.48, 0.19)
	weights[Biome.DESERT] = desert
	# Extreme desert can exist without a closed basin; that structural context
	# strongly favors its saline variant. The aridity envelope is mandatory.
	weights[Biome.SALAR] = desert * (0.8 + 4.0 * basin) * 2.4 * (1.0 - smoothstep(0.09, 0.30, p))
	weights[Biome.TEMPERATE] = 0.02 + _bell(t, 12.0, 12.0) * _bell(p, 0.58, 0.34)
	weights[Biome.WETLAND] = _bell(t, 21.0, 17.0) * _bell(p, 0.88, 0.19) * lowland * \
		(1.0 - rugged) * (0.65 + 0.35 * ocean) * 2.1
	weights[Biome.TAIGA] = _bell(t, -3.0, 10.0) * _bell(p, 0.52, 0.35) * (1.0 - 0.35 * ocean)
	weights[Biome.TUNDRA] = _bell(t, -17.0, 11.0) * (1.0 - 0.20 * p)
	weights[Biome.ALPINE] = _bell(t, 0.0, 15.0) * smoothstep(580.0, 1150.0, altitude) * \
		(1.0 - smoothstep(0.76, 0.94, latitude)) * 2.0
	weights[Biome.POLAR] = _bell(t, -27.0, 14.0) * smoothstep(0.68, 0.89, latitude) * 2.0
	var total := 0.0
	var first := -1
	var second := -1
	var best := -1.0
	var runner_up := -1.0
	for i in range(weights.size()):
		var value := weights[i]
		total += value
		if value > best:
			runner_up = best
			second = first
			best = value
			first = i
		elif value > runner_up:
			runner_up = value
			second = i
	for i in range(weights.size()):
		weights[i] /= total
	output.dominant = first
	output.secondary = second
	output.top_pair_mix = best / (best + runner_up)
