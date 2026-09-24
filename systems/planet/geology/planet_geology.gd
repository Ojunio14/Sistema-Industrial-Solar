class_name PlanetGeology
extends RefCounted
## Structural geology built BEFORE natural relief, from continental context.
## Depois da construção, províncias e índice espacial são somente leitura.
## Vector4 da consulta: ID local, maturidade 0..1, influência 0..1, tipo.

const GENERATOR_VERSION := 3
const SEED_SALT := 0x47454F32 # GEO2; não reutiliza IDs da antiga fundação.
enum Type { OCEANIC, CRATON, OROGEN, SEDIMENTARY, IGNEOUS, PLATEAU, CLOSED_BASIN, FORMER_MARINE, PLATFORM }
const TYPE_NAMES := ["Fundo oceânico", "Interior antigo", "Cinturão montanhoso", "Bacia sedimentar", "Ígneo/vulcânico", "Planalto estrutural", "Bacia fechada", "Antiga região marinha", "Plataforma continental"]
const COUNTS := [0, 8, 9, 8, 2, 5, 3, 5]
const RADII := [0.0, 0.43, 0.23, 0.32, 0.12, 0.25, 0.19, 0.18]
const MATURITY := [0.35, 0.89, 0.30, 0.68, 0.22, 0.72, 0.61, 0.76]
const BINS := 8

class Province:
	extends RefCounted
	var id: int
	var kind: int
	var center: Vector3
	var radius: float
	var age: float
	var strength: float
	var axis: Vector3
	var side: Vector3
	var phase: float

var _planet_seed: int
var _geology_seed: int
var _sea_level: float
var _continental: ContinentalShape
var _direct_relief: TerrainRelief
var _structure := FastNoiseLite.new()
var _uplift := FastNoiseLite.new()
var _provinces: Array[Province] = []
var _buckets: Array[Array] = []

func _init(definition: PlanetDefinition, geology_seed_override: int = -1) -> void:
	_planet_seed = definition.seed
	_geology_seed = geology_seed_override if geology_seed_override >= 0 else definition.seed ^ SEED_SALT
	_sea_level = definition.sea_level_m
	_continental = ContinentalShape.new(definition.duplicate(true))
	_direct_relief = TerrainRelief.new(definition)
	ContinentalShape._configure(_structure,_geology_seed+311,2)
	ContinentalShape._configure(_uplift,_geology_seed+719,2)
	_generate()
	_build_index()

static func type_of(local_id: int) -> int:
	return local_id & 15

func stable_key(local_id: int) -> String:
	return "geo%d:%d:%d:%d" % [GENERATOR_VERSION, _planet_seed, _geology_seed, local_id]

func describe(local_id: int) -> Dictionary:
	if local_id == 0 or local_id == Type.PLATFORM:
		return {"id": local_id, "key": stable_key(local_id), "type": type_of(local_id), "background": true}
	for p in _provinces:
		if p.id == local_id:
			return {"id": p.id, "key": stable_key(p.id), "type": p.kind,
				"center": p.center, "radius": p.radius, "age": p.age, "strength": p.strength,
				"axis": p.axis, "side": p.side, "phase": p.phase}
	return {}

func descriptors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for p in _provinces:
		result.append(describe(p.id))
	return result

func sample(direction: Vector3) -> Vector4:
	var continental := _continental.sample(direction)
	return sample_with_surface(direction, _direct_relief.sample(direction,continental,self))

## Borrowed read-only bucket; no allocation. Relief consumes descriptors, never
## the categorical province ID or a classification derived from final height.
func relief_candidates(direction: Vector3) -> Array:
	var p := direction.normalized()
	var ix := clampi(int((p.x+1.0)*4.0),0,7)
	var iy := clampi(int((p.y+1.0)*4.0),0,7)
	var iz := clampi(int((p.z+1.0)*4.0),0,7)
	return _buckets[ix+BINS*(iy+BINS*iz)]

## Seeding potential only, not another terrain authority. Coarse structural
## fields rank descriptor locations before relief exists, breaking the cycle.
func _structural_surface(direction: Vector3) -> Vector4:
	var c := _continental.sample(direction)
	if c.x<=_sea_level+5.0:
		return Vector4(c.x,c.y,0.0,0.0)
	var p := direction.normalized()
	var belt := smoothstep(0.45,0.88,1.0-absf(_structure.get_noise_3dv(p*3.1)))*c.w
	var plateau := smoothstep(0.25,0.68,_uplift.get_noise_3dv(p*4.2)*0.5+0.5)*c.w
	return Vector4(c.x+300.0*belt+120.0*plateau,c.y,belt,plateau)

func sample_position(local_position: Vector3) -> Vector4:
	return sample(local_position.normalized())

## Worker-safe: só lê números/vetores imutáveis, sem Resource, Node, RNG ou scratch global.
func sample_with_surface(direction: Vector3, surface: Vector4) -> Vector4:
	var p := direction.normalized()
	var land := smoothstep(-20.0, 35.0, surface.x - _sea_level)
	var background_id := Type.PLATFORM if surface.x > _sea_level else Type.OCEANIC
	var background_age := lerpf(0.35, 0.65, land)
	var background_weight := maxf(0.12, 1.0 - land)
	var best_id := background_id
	var best_weight := background_weight
	var total := background_weight
	var age_sum := background_age * background_weight
	var ix := clampi(int((p.x + 1.0) * 4.0), 0, 7)
	var iy := clampi(int((p.y + 1.0) * 4.0), 0, 7)
	var iz := clampi(int((p.z + 1.0) * 4.0), 0, 7)
	for province: Province in _buckets[ix + BINS * (iy + BINS * iz)]:
		var chord2 := 2.0 - 2.0 * clampf(p.dot(province.center), -1.0, 1.0)
		var radius2 := province.radius * province.radius
		if chord2 >= radius2:
			continue
		var falloff := 1.0 - chord2 / radius2
		var suitability := _suitability(province.kind, surface)
		var weight := falloff * falloff * suitability * province.strength * land
		if weight <= 0.0:
			continue
		total += weight
		age_sum += weight * province.age
		if weight > best_weight:
			best_weight = weight
			best_id = province.id
	return Vector4(best_id, clampf(age_sum / total, 0.0, 1.0),
		clampf(best_weight / total, 0.0, 1.0), type_of(best_id))

static func _suitability(kind: int, s: Vector4) -> float:
	match kind:
		Type.CRATON: return 0.7 + 0.3 * (1.0 - s.z)
		Type.OROGEN: return 0.35 + 3.0 * s.z
		Type.SEDIMENTARY: return (1.0 - 0.8 * s.z) * (1.0 - 0.4 * s.w)
		Type.IGNEOUS: return 0.55 + 1.8 * maxf(s.z, s.w)
		Type.PLATEAU: return 0.45 + 2.0 * s.w
		Type.CLOSED_BASIN: return 0.9 * (1.0 - 0.6 * s.z)
		Type.FORMER_MARINE: return 0.5 + 0.5 * (1.0 - s.y)
	return 0.0

func _generate() -> void:
	# Equal-area candidates ranked from continents and structural potential only.
	var candidates: Array = []
	for i in range(3072):
		var y := 1.0 - 2.0 * (float(i) + 0.5) / 3072.0
		var angle := float(i) * 2.399963229728653
		var radial := sqrt(maxf(0.0, 1.0 - y * y))
		var direction := Vector3(cos(angle) * radial, y, sin(angle) * radial)
		var s := _structural_surface(direction)
		var h := s.x - _sea_level
		if h <= 5.0 or s.y < 0.48:
			continue
		var tangent := Vector3.UP.cross(direction).normalized()
		if tangent.length_squared() < 0.1:
			tangent = Vector3.RIGHT.cross(direction).normalized()
		var bitangent := direction.cross(tangent)
		var n1 := _structural_surface((direction + tangent * 0.035).normalized()).x - _sea_level
		var n2 := _structural_surface((direction - tangent * 0.035).normalized()).x - _sea_level
		var n3 := _structural_surface((direction + bitangent * 0.035).normalized()).x - _sea_level
		var n4 := _structural_surface((direction - bitangent * 0.035).normalized()).x - _sea_level
		var relief := absf(n1 - n2) + absf(n3 - n4)
		var depression := maxf(0.0, (n1 + n2 + n3 + n4) * 0.25 - h)
		candidates.append({"direction": direction, "h": h, "land": s.y,
			"mountain": s.z, "plateau": s.w, "relief": relief, "depression": depression,
			"jitter": float(_hash(i + _geology_seed) & 65535) / 65535.0})
	for kind in range(Type.CRATON, Type.FORMER_MARINE + 1):
		var ranked := candidates.duplicate()
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _candidate_score(kind, a) > _candidate_score(kind, b))
		var count := 0
		for candidate: Dictionary in ranked:
			if count >= COUNTS[kind]:
				break
			if _candidate_score(kind, candidate) <= 0.0:
				break
			var center: Vector3 = candidate.direction
			var separated := true
			for other: Province in _provinces:
				if other.kind == kind and center.dot(other.center) > cos(RADII[kind] * 1.3):
					separated = false
					break
			if not separated:
				continue
			var province := Province.new()
			province.kind = kind
			province.id = (count + 1) * 16 + kind
			province.center = center
			province.radius = RADII[kind] * (0.9 + 0.2 * candidate.jitter)
			province.age = clampf(MATURITY[kind] + (candidate.jitter - 0.5) * 0.14, 0.0, 1.0)
			if kind == Type.OROGEN:
				province.age = lerpf(0.18,0.82,candidate.jitter)
			var tangent := Vector3.UP.cross(center).normalized()
			if tangent.is_zero_approx(): tangent=Vector3.RIGHT.cross(center).normalized()
			province.phase = candidate.jitter*TAU
			province.axis = tangent.rotated(center,province.phase)
			province.side = center.cross(province.axis).normalized()
			province.strength = 1.0 if kind == Type.CRATON else 1.6
			if kind == Type.IGNEOUS:
				province.strength = 2.0
			_provinces.append(province)
			count += 1

static func _candidate_score(kind: int, c: Dictionary) -> float:
	var h: float = c.h
	var jitter: float = c.jitter * 0.20
	match kind:
		Type.CRATON: return (c.land - 0.78) * 3.0 + minf(h / 400.0, 0.7) - c.mountain - c.plateau * 0.5 - c.relief / 800.0 + jitter
		Type.OROGEN: return c.mountain * 4.0 + c.relief / 350.0 + minf(h / 500.0, 0.5) + jitter
		Type.SEDIMENTARY: return 1.0 - absf(h - 110.0) / 280.0 - c.mountain * 2.0 - c.relief / 700.0 + jitter
		Type.IGNEOUS: return c.mountain * 2.0 + c.plateau * 2.0 + minf(h / 450.0, 0.8) + jitter
		Type.PLATEAU: return c.plateau * 4.0 + minf(h / 450.0, 0.7) + jitter
		Type.CLOSED_BASIN: return c.depression / 120.0 + 0.7 - absf(h - 100.0) / 250.0 - c.mountain + jitter
		Type.FORMER_MARINE: return 1.4 - absf(h - 45.0) / 160.0 - absf(c.land - 0.72) + jitter
	return 0.0

static func _hash(value: int) -> int:
	var x := value & 0x7fffffff
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0x7fffffff
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0x7fffffff
	return x ^ (x >> 16)

func _build_index() -> void:
	for z in range(BINS):
		for y in range(BINS):
			for x in range(BINS):
				var center := (Vector3(x, y, z) + Vector3.ONE * 0.5) * (2.0 / BINS) - Vector3.ONE
				var bucket: Array[Province] = []
				for province in _provinces:
					# Qualquer direção deste cubo fica dentro deste raio do centro.
					if center.distance_to(province.center) <= province.radius + sqrt(3.0) / BINS:
						bucket.append(province)
				_buckets.append(bucket)
