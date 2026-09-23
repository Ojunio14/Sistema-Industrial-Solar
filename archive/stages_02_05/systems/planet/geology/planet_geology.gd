class_name PlanetGeology
extends RefCounted
## Surface-only structural geology. Immutable after construction; no terrain
## back-reference, face identity, camera, per-query allocation or random state.
## Query Vector4 = (local province ID, blended maturity, dominant weight, delta m).
const GENERATOR_VERSION := 1
const SEED_SALT := 0x47454F31 # "GEO1", one documented subseed namespace.
const MAX_DISPLACEMENT := 260.0
const MIN_DISPLACEMENT := -180.0
enum Type { OCEANIC, CRATON, OROGEN, SEDIMENTARY, IGNEOUS, PLATEAU, CLOSED_BASIN, FORMER_MARINE, PLATFORM }
const TYPE_NAMES := ["Oceanic basement", "Ancient interior", "Orogenic belt",
	"Sedimentary basin", "Igneous/volcanic", "Structural plateau",
	"Closed basin", "Former marine", "Continental platform"]

class Province:
	extends RefCounted
	var id: int
	var kind: int
	var source_form: int
	var center: Vector3
	var u: Vector3
	var v: Vector3
	var length: float
	var width: float
	var age: float
	var phase: float
	var amplitude: float
	var priority := 1.0

var _seed: int
var _domain: Dictionary
var _provinces: Array[Province] = []
var _by_id: Dictionary = {}
var _buckets: Array[Array] = []
var _macro_phase: float

func _init(seed_value: int, macro: PlanetTerrain) -> void:
	_seed = seed_value
	_domain = macro.continental_snapshot()
	_macro_phase = _domain.phase
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ SEED_SALT
	var anchors := macro.get_anchors()
	for i in range(anchors.size()):
		var center := anchors[i]
		var u := center.cross(Vector3.UP).normalized()
		_add((i + 1) * 100, Type.CRATON, PlanetTerrain.Form.PLAIN, center, u,
			0.43, 0.36, rng.randf_range(0.82, 0.98), 35, rng)
	for source in macro.structural_blueprint():
		var owner := 0
		var closest := -2.0
		for i in range(anchors.size()):
			var dot: float = anchors[i].dot(source.center)
			if dot > closest:
				closest = dot
				owner = i
		var key: int = (owner + 1) * 100 + source.kind
		match source.kind:
			PlanetTerrain.Form.CHAIN, PlanetTerrain.Form.RANGE:
				var age := rng.randf_range(0.12, 0.42) if source.kind == PlanetTerrain.Form.CHAIN else rng.randf_range(0.65, 0.90)
				_add(key, Type.OROGEN, source.kind, source.center, source.u,
					source.length * 1.12, source.width * 1.6, age, source.amplitude, rng)
			PlanetTerrain.Form.PLATEAU:
				var kind := Type.IGNEOUS if owner == 2 else Type.PLATEAU
				_add(key, kind, source.kind, source.center, source.u, source.length, source.width,
					rng.randf_range(0.18, 0.35) if kind == Type.IGNEOUS else rng.randf_range(0.55, 0.90), 190, rng)
			PlanetTerrain.Form.BASIN:
				_add(key, Type.CLOSED_BASIN if owner == 0 else Type.SEDIMENTARY, source.kind,
					source.center, source.u, source.length * 1.25, source.width * 1.25,
					rng.randf_range(0.45, 0.75), 130, rng)
			PlanetTerrain.Form.VALLEY:
				_add(key, Type.SEDIMENTARY, source.kind, source.center, source.u,
					source.length * 1.2, source.width * 1.8, rng.randf_range(0.4, 0.7), 85, rng)
			PlanetTerrain.Form.EXCEPTIONAL:
				_add(key, Type.IGNEOUS, source.kind, source.center, source.u,
					source.length, source.width, rng.randf_range(0.08, 0.25), 240, rng)
	# Former marine provinces: select emerged low margins in each mainland,
	# not random patches or a classification from current climate.
	for i in range(anchors.size()):
		var center := anchors[i]
		var u := center.cross(Vector3.UP).normalized()
		var v := center.cross(u)
		var selected := Vector3.ZERO
		var best := INF
		for j in range(48):
			var angle := j * TAU / 48.0
			var candidate := (center + (u * cos(angle) + v * sin(angle)) * 0.46).normalized()
			var fields := macro.sample_fields(candidate)
			if fields.y > 0.025 and fields.y < 0.16 and fields.x > 20 and fields.x < 260:
				var score := absf(fields.y - 0.075)
				if score < best:
					best = score
					selected = candidate
		if not selected.is_zero_approx():
			_add((i + 1) * 100 + 90, Type.FORMER_MARINE, PlanetTerrain.Form.PLAIN,
				selected, u, 0.17, 0.12, rng.randf_range(0.60, 0.85), 55, rng)
	_build_index()

func _add(key: int, kind: int, form: int, center: Vector3, u: Vector3,
		length: float, width: float, age: float, amplitude: float, rng: RandomNumberGenerator) -> void:
	var p := Province.new()
	p.id = key * 16 + kind
	assert(p.id < (1 << 24) and not _by_id.has(p.id))
	p.kind = kind
	p.source_form = form
	p.center = center
	p.u = (u - center * u.dot(center)).normalized()
	p.v = center.cross(p.u)
	p.length = length
	p.width = width
	p.age = age
	p.amplitude = amplitude
	p.phase = rng.randf_range(-PI, PI)
	p.priority = 0.9 if kind == Type.CRATON else 1.8
	if kind == Type.IGNEOUS:
		p.priority = 2.6
	_provinces.append(p)
	_by_id[p.id] = p

func _build_index() -> void:
	for z in range(8):
		for y in range(8):
			for x in range(8):
				var cell := (Vector3(x, y, z) + Vector3.ONE * 0.5) * 0.25 - Vector3.ONE
				var selected: Array[Province] = []
				for p in _provinces:
					var support := maxf(p.length, p.width)
					var chord := sqrt(2.0 - 2.0 * sqrt(1.0 - support * support))
					if cell.distance_to(p.center) <= chord + sqrt(3.0) / 8.0 + 0.00001:
						selected.append(p)
				_buckets.append(selected)

static func type_of(local_id: int) -> int:
	return local_id & 15

func stable_key(local_id: int) -> String:
	return "geo%d:%d:%d" % [GENERATOR_VERSION, _seed, local_id]

func describe(local_id: int) -> Dictionary:
	if local_id == 0:
		return {"id": 0, "key": stable_key(0), "type": Type.OCEANIC, "age": 0.35, "background": true}
	var background_index := (local_id >> 4) - 900
	if type_of(local_id) == Type.PLATFORM and background_index >= 0 and background_index < _domain.backgrounds.size():
		return {"id": local_id, "key": stable_key(local_id), "type": Type.PLATFORM, "age": 0.65,
			"direction": _domain.backgrounds[background_index], "background": true}
	if not _by_id.has(local_id):
		return {}
	var p: Province = _by_id[local_id]
	return {"id": p.id, "key": stable_key(p.id), "type": p.kind, "age": p.age,
		"direction": p.center, "length": p.length, "width": p.width, "source_form": p.source_form}

func descriptors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for p in _provinces:
		result.append(describe(p.id))
	return result

func continentality(d: Vector3) -> float:
	return PlanetTerrain.continental_field(d, _domain.main, _domain.minor,
		_domain.seas, _domain.phase, _domain.bias)

func query_position(position: Vector3) -> Vector4:
	assert(position.is_finite() and not position.is_zero_approx())
	return query_direction(position.normalized())

func query_direction(d: Vector3) -> Vector4:
	return query_with_continentality(d, continentality(d))

## Shared context supplied only by the authoritative terrain; avoids re-querying
## continental fields per vertex. Public consumers normally use query_direction.
func query_with_continentality(d: Vector3, c: float) -> Vector4:
	if c <= 0.0:
		return Vector4(0, 0.35, 1.0, 0.0)
	var domain_weight := smoothstep(0.0, 0.075, c)
	var id := 24 if c > 0.0 else 0
	var best := 0.25
	var total := 0.25
	var age_sum := lerpf(0.35, 0.65, domain_weight) * total
	var delta := 0.0
	for p: Province in _buckets[PlanetTerrain._bucket(d)]:
		if d.dot(p.center) < 0.85:
			continue
		var x := d.dot(p.u) / p.length
		var y := d.dot(p.v) / p.width
		var q := x * x + y * y
		if q >= 1.0:
			continue
		var w := (1.0 - smoothstep(0.15, 1.0, q)) * domain_weight * p.priority
		if p.kind == Type.CRATON:
			w *= smoothstep(0.02, 0.15, c)
		total += w
		age_sum += w * p.age
		delta += w * _deformation(p, x, y, q)
		# Deterministic ties retain construction order; identity never drives height.
		if w > best:
			best = w
			id = p.id
	var displacement := clampf(delta / maxf(1.0, total), MIN_DISPLACEMENT, MAX_DISPLACEMENT)
	displacement *= smoothstep(0.0, 0.045, c)
	if id == 24:
		# Stable background domains, not one shared identity for every continent.
		var closest := -2.0
		var backgrounds: PackedVector3Array = _domain.backgrounds
		for i in range(backgrounds.size()):
			var dot := d.dot(backgrounds[i])
			if dot > closest:
				closest = dot
				id = (900 + i) * 16 + Type.PLATFORM
	return Vector4(id, age_sum / total, best / total, displacement)

func _deformation(p: Province, x: float, y: float, q: float) -> float:
	match p.kind:
		Type.CRATON:
			return p.amplitude * (1.0 - q) * sin(x * 3.0 + p.phase) * cos(y * 2.0) * (1.0 - p.age)
		Type.OROGEN:
			var original_q := pow(x * 1.12, 2.0) + pow(y * 1.6, 2.0)
			var original := p.amplitude * pow(maxf(0.0, 1.0 - original_q), 2.0) * (0.88 + 0.12 * cos(x * 1.12 * 13.0 + _macro_phase))
			var transverse := y * lerpf(1.85, 1.30, p.age)
			var shaped := maxf(0.0, 1.0 - pow(x * 1.12, 2.0) - transverse * transverse)
			var peaks := 0.86 + 0.14 * cos(x * lerpf(23.0, 8.0, p.age) + p.phase)
			return p.amplitude * lerpf(1.18, 0.88, p.age) * pow(shaped, lerpf(2.4, 1.7, p.age)) * peaks - original
		Type.IGNEOUS:
			# Localized volcanic edifice/plateau, with a shallow central depression.
			var cone := pow(1.0 - q, 2.0)
			if p.source_form == PlanetTerrain.Form.PLATEAU:
				cone = 1.0 - smoothstep(0.2, 1.0, q)
			return p.amplitude * (cone - 0.18 * exp(-q * 60.0)) * (1.0 - 0.3 * p.age)
		Type.SEDIMENTARY, Type.FORMER_MARINE:
			return -p.amplitude * (1.0 - smoothstep(0.25, 1.0, q)) * (0.8 + 0.2 * cos(x * 2.0 + p.phase))
		Type.CLOSED_BASIN:
			return -p.amplitude * pow(1.0 - q, 2.0) + 30.0 * sin(q * PI) * q
		Type.PLATEAU:
			return p.amplitude * (1.0 - smoothstep(0.25, 1.0, q)) * (0.45 + 0.15 * sin(x * 3.0 + p.phase)) * (1.0 - 0.3 * p.age)
	return 0.0

func error_estimate(d: Vector3, patch_span: float, cell_span: float) -> float:
	var curvature := 0.0
	for p in _provinces:
		if d.distance_to(p.center) <= patch_span + maxf(p.length, p.width) * 1.04:
			curvature = maxf(curvature, 16.0 * MAX_DISPLACEMENT / (p.width * p.width))
	return minf(MAX_DISPLACEMENT - MIN_DISPLACEMENT, curvature * cell_span * cell_span * 0.25)
