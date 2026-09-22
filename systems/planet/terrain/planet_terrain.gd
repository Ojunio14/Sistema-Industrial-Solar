class_name PlanetTerrain
extends RefCounted
## Authoritative radial heightfield, in meters. Construct once, then read only.
## Query arguments are unit directions: no face/LOD/camera or random state.

const DEFAULT_SEED := 73129
const MIN_HEIGHT := -3100.0
const MAX_HEIGHT := 2200.0
const CALIBRATION_SAMPLES := 4096
const BUCKETS := 8
enum Form { OCEAN, PLAIN, HILLS, PLATEAU, RANGE, CHAIN, VALLEY, BASIN, EXCEPTIONAL }

class Region:
	extends RefCounted
	var center: Vector3
	var u: Vector3
	var v: Vector3
	var length: float
	var width: float
	var amplitude: float
	var kind: int

var _seed: int
var _rotation: Basis
var _caps := PackedVector4Array() # xyz = center; w = angular radius
var _islands := PackedVector4Array()
var _seas := PackedVector4Array()
var _regions: Array[Region] = []
var _deep := PackedVector4Array()
var _anchors := PackedVector3Array()
var _bias := 0.0
var _phase := 0.0
var _main_field := PackedVector4Array()
var _minor_field := PackedVector4Array()
var _sea_field := PackedVector4Array()
var _main_buckets: Array[PackedVector4Array] = []
var _minor_buckets: Array[PackedVector4Array] = []
var _sea_buckets: Array[PackedVector4Array] = []
var _region_buckets: Array[Array] = []

func _init(planet_seed: int = DEFAULT_SEED) -> void:
	_seed = planet_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = planet_seed
	_rotation = Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI)))
	_phase = rng.randf_range(-PI, PI)
	for i in range(5):
		var center := (_rotation * uniform_direction(i, 5)).normalized()
		_anchors.append(center)
		var u := center.cross(Vector3.UP).normalized()
		var v := center.cross(u)
		var angle := rng.randf_range(-PI, PI)
		u = u.rotated(center, angle)
		v = center.cross(u)
		_caps.append(Vector4(center.x, center.y, center.z, rng.randf_range(0.48, 0.57)))
		for j in range(3):
			var lobe := (center + u * (0.36 if j == 0 else -0.30) + v * rng.randf_range(-0.32, 0.32)).normalized()
			_caps.append(Vector4(lobe.x, lobe.y, lobe.z, rng.randf_range(0.24, 0.38)))
		# Rotate regional layout independently of the coastline; vary presence.
		u = u.rotated(center, rng.randf_range(-0.8, 0.8))
		v = center.cross(u)
		_add_region(center, u, v, Vector2(-0.17, 0.10), 0.17, 0.13, 260.0, Form.HILLS)
		if i != 3:
			_add_region(center, u, v, Vector2(0.13, 0.12), rng.randf_range(0.12, 0.18), 0.11, rng.randf_range(450, 700), Form.PLATEAU)
		# Full longitudinal support 0.2..0.5 radians = 10..25 km at R=50 km.
		_add_region(center, u, v, Vector2(0.12, -0.15), rng.randf_range(0.16, 0.25), 0.055, rng.randf_range(950, 1300), Form.CHAIN)
		_add_region(center, v, -u, Vector2(-0.21, 0.0), 0.12, 0.065, 520.0, Form.RANGE)
		_add_region(center, u, v, Vector2(-0.07, -0.22), 0.15, 0.045, -260.0, Form.VALLEY)
		if i % 2 == 0:
			_add_region(center, u, v, Vector2(0.0, 0.30), 0.12, 0.10, -420.0, Form.BASIN)
		if i == 0:
			_add_region(center, u, v, Vector2(0.33, 0.0), 0.085, 0.06, 1800.0, Form.EXCEPTIONAL)
		if i < 2:
			var sea := (center + v * -0.02).normalized()
			_seas.append(Vector4(sea.x, sea.y, sea.z, 0.075 + i * 0.02))
	# Pick ocean gaps by farthest-candidate search; explicit smaller structures.
	for i in range(8):
		var best := Vector3.ZERO
		var clearance := 1.0
		for j in range(256):
			var candidate := (_rotation * uniform_direction(j, 256)).normalized()
			var field := maxf(_cap_field(candidate, _caps), _cap_field(candidate, _islands))
			if field < clearance:
				clearance = field
				best = candidate
		var size := 0.22 if i < 2 else (0.12 if i < 4 else 0.055)
		_islands.append(Vector4(best.x, best.y, best.z, size))
		if i >= 4:
			var tangent := best.cross(Vector3.UP).normalized()
			for j in range(1, 5):
				var island := (best + tangent * j * 0.065 + best.cross(tangent) * sin(j * 1.1) * 0.035).normalized()
				_islands.append(Vector4(island.x, island.y, island.z, rng.randf_range(0.018, 0.032)))
		if i < 3:
			var deep_center := (best - best.cross(Vector3.UP).normalized() * 0.30).normalized()
			_deep.append(Vector4(deep_center.x, deep_center.y, deep_center.z, 0.20 if i == 0 else 0.32))
	_main_field = _compile_caps(_caps)
	_minor_field = _compile_caps(_islands)
	_sea_field = _compile_caps(_seas)
	_main_buckets = _make_buckets(_main_field)
	_minor_buckets = _make_buckets(_minor_field)
	_sea_buckets = _make_buckets(_sea_field)
	for z in range(BUCKETS):
		for y in range(BUCKETS):
			for x in range(BUCKETS):
				var center := (Vector3(x, y, z) + Vector3.ONE * 0.5) * (2.0 / BUCKETS) - Vector3.ONE
				var selected: Array[Region] = []
				for region in _regions:
					var tangent_support := maxf(region.length, region.width)
					var chord_support := sqrt(2.0 - 2.0 * sqrt(1.0 - tangent_support * tangent_support))
					if center.distance_to(region.center) <= chord_support + sqrt(3.0) / BUCKETS + 0.00001:
						selected.append(region)
				_region_buckets.append(selected)
	_calibrate()

static func _make_buckets(caps: PackedVector4Array) -> Array[PackedVector4Array]:
	# Exact broad phase in global Cartesian direction space. A discarded affine
	# cap cannot win anywhere in this CLOSED cell. No face identity, query cache,
	# approximation or terrain change at bin boundaries.
	var result: Array[PackedVector4Array] = []
	for z in range(BUCKETS):
		for y in range(BUCKETS):
			for x in range(BUCKETS):
				var center := (Vector3(x, y, z) + Vector3.ONE * 0.5) * (2.0 / BUCKETS) - Vector3.ONE
				var lower := -2.0
				for cap in caps:
					var reach := (absf(cap.x) + absf(cap.y) + absf(cap.z)) / BUCKETS
					lower = maxf(lower, center.x * cap.x + center.y * cap.y + center.z * cap.z - cap.w - reach)
				var selected := PackedVector4Array()
				for cap in caps:
					var reach := (absf(cap.x) + absf(cap.y) + absf(cap.z)) / BUCKETS
					if center.x * cap.x + center.y * cap.y + center.z * cap.z - cap.w + reach >= lower - 0.00001:
						selected.append(cap)
				result.append(selected)
	return result

static func _bucket(d: Vector3) -> int:
	return clampi(int((d.x + 1.0) * 4.0), 0, 7) + 8 * clampi(int((d.y + 1.0) * 4.0), 0, 7) + 64 * clampi(int((d.z + 1.0) * 4.0), 0, 7)

static func _compile_caps(caps: PackedVector4Array) -> PackedVector4Array:
	var result := PackedVector4Array()
	for cap in caps:
		result.append(Vector4(cap.x, cap.y, cap.z, cos(cap.w)) / sin(cap.w))
	return result

static func _field(d: Vector3, caps: PackedVector4Array) -> float:
	var value := -2.0
	for cap in caps:
		value = maxf(value, d.x * cap.x + d.y * cap.y + d.z * cap.z - cap.w)
	return value

static func uniform_direction(index: int, count: int) -> Vector3:
	var y := 1.0 - 2.0 * (index + 0.5) / count
	var r := sqrt(maxf(0.0, 1.0 - y * y))
	var angle := index * PI * (3.0 - sqrt(5.0))
	return Vector3(cos(angle) * r, y, sin(angle) * r)

func get_seed() -> int:
	return _seed

func get_anchors() -> PackedVector3Array:
	return _anchors.duplicate()

func debug_landmarks() -> Array[Dictionary]:
	# Diagnostic copies, never exposed as mutable production descriptors.
	var result: Array[Dictionary] = []
	var seen := {}
	for region in _regions:
		if not seen.has(region.kind):
			seen[region.kind] = true
			result.append({"name": Form.keys()[region.kind].to_lower(), "direction": region.center, "kind": region.kind})
	result.append({"name": "archipelago", "direction": Vector3(_islands[4].x, _islands[4].y, _islands[4].z)})
	result.append({"name": "inland_sea", "direction": Vector3(_seas[0].x, _seas[0].y, _seas[0].z)})
	result.append({"name": "ocean", "direction": Vector3(_deep[0].x, _deep[0].y, _deep[0].z)})
	return result

func _add_region(center: Vector3, u: Vector3, v: Vector3, offset: Vector2, length: float, width: float, amplitude: float, kind: int) -> void:
	var region := Region.new()
	region.center = (center + u * offset.x + v * offset.y).normalized()
	region.u = (u - region.center * u.dot(region.center)).normalized()
	region.v = region.center.cross(region.u)
	region.length = length
	region.width = width
	region.amplitude = amplitude
	region.kind = kind
	_regions.append(region)

static func _cap_field(d: Vector3, caps: PackedVector4Array) -> float:
	var value := -2.0
	for cap in caps:
		# Continuous signed field in angular-scale units, no acos or face chart.
		value = maxf(value, (d.dot(Vector3(cap.x, cap.y, cap.z)) - cos(cap.w)) / sin(cap.w))
	return value

func _warp(d: Vector3) -> float:
	return 0.025 * sin(d.x * 8.0 + d.y * 3.0 + _phase) * sin(d.z * 7.0 - d.y * 4.0 - _phase)

func _calibrate() -> void:
	# Only construction: approximately equal-area directions, not mesh vertices.
	var main := PackedFloat32Array()
	var minor := PackedFloat32Array()
	var seas := PackedFloat32Array()
	for i in range(CALIBRATION_SAMPLES):
		var d := uniform_direction(i, CALIBRATION_SAMPLES)
		main.append(_field(d, _main_field) + _warp(d))
		minor.append(_field(d, _minor_field))
		seas.append(-_field(d, _sea_field))
	var low := -0.15
	var high := 0.15
	for iteration in range(18):
		var middle := (low + high) * 0.5
		var land := 0
		for i in range(CALIBRATION_SAMPLES):
			if minf(maxf(main[i] + middle, minor[i]), seas[i]) > 0.0:
				land += 1
		if float(land) / CALIBRATION_SAMPLES < 0.453:
			low = middle
		else:
			high = middle
	_bias = (low + high) * 0.5

func continentality(d: Vector3) -> float:
	var bucket := _bucket(d)
	return minf(maxf(_field(d, _main_buckets[bucket]) + _warp(d) + _bias, _field(d, _minor_buckets[bucket])), -_field(d, _sea_buckets[bucket]))

func sample(d: Vector3) -> float:
	return sample_fields(d).x

## x height(m), y continental field, z Form, w coastal proximity.
## Vector4 is a value; no descriptors/RNG/arrays/dictionaries created per query.
func sample_fields(d: Vector3) -> Vector4:
	var c := continentality(d)
	var coast := 1.0 - smoothstep(0.0, 0.055, absf(c))
	if c <= 0.0:
		var depth := 180.0 + 1050.0 * smoothstep(0.0, 0.18, -c)
		depth += 250.0 * sin(d.x * 4.0 + _phase) * sin(d.z * 5.0)
		for i in range(_deep.size()):
			var cap := _deep[i]
			var distance_squared := d.distance_squared_to(Vector3(cap.x, cap.y, cap.z)) / (cap.w * cap.w)
			depth += (1800.0 if i == 0 else 1000.0) * pow(maxf(0.0, 1.0 - distance_squared), 2.0)
		return Vector4(maxf(MIN_HEIGHT, -maxf(50.0, depth) * smoothstep(0.0, 0.045, -c)), c, Form.OCEAN, coast)
	var height := 190.0 + 65.0 * sin(d.x * 9.0 + _phase) * sin(d.y * 8.0 - d.z * 4.0)
	var form := Form.PLAIN
	var strongest := 0.0
	for region: Region in _region_buckets[_bucket(d)]:
		if d.dot(region.center) < 0.93:
			continue
		var x := d.dot(region.u) / region.length
		var y := d.dot(region.v) / region.width
		var q := x * x + y * y
		if q >= 1.0:
			continue
		var weight := 1.0 - smoothstep(0.30, 1.0, q)
		if region.kind == Form.CHAIN or region.kind == Form.RANGE or region.kind == Form.EXCEPTIONAL:
			weight = pow(1.0 - q, 2.0) * (0.88 + 0.12 * cos(x * 13.0 + _phase))
		elif region.kind == Form.HILLS:
			weight *= 0.55 + 0.45 * sin(d.dot(region.u) * 85.0 + _phase) * sin(d.dot(region.v) * 70.0)
		var contribution := region.amplitude * weight
		height += contribution
		if absf(contribution) > strongest:
			strongest = absf(contribution)
			form = region.kind
	height *= smoothstep(0.0, 0.045, c)
	return Vector4(clampf(height, MIN_HEIGHT, MAX_HEIGHT), c, form, coast)

func patch_error(id: PatchId) -> float:
	# Conservative engineering estimate of interpolation residual, not altitude.
	# Squared cell span preserves convergence. Regional sharp forms carry a larger
	# curvature envelope; global range caps error on unresolved coarse patches.
	var d := PlanetMath.face_uv_to_direction(id.face, id.get_uv_bounds().get_center())
	var span := 1.42 / float(1 << id.level)
	var curvature := 600000.0
	if absf(continentality(d)) < span + 0.20:
		curvature = 4000000.0
	for region in _regions:
		if d.distance_to(region.center) < span + maxf(region.length, region.width):
			curvature = maxf(curvature, 12.0 * absf(region.amplitude) / (region.width * region.width))
			if region.kind == Form.HILLS:
				curvature = maxf(curvature, 2.0 * absf(region.amplitude) * (85.0 * 85.0 + 70.0 * 70.0))
	var cell := 2.0 / (32.0 * (1 << id.level))
	return minf(MAX_HEIGHT - MIN_HEIGHT, curvature * cell * cell * 0.25)
