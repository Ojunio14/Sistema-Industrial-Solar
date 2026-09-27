class_name MiningTransitionJob
extends RefCounted
## CPU ownership: subtract the chart rectangle from the actual visible global
## triangles, then zipper their cut polyline to the 2 m natural zone perimeter.
## No discard, overlay, depth offset, duplicate ground, or natural-height clone.
const COLLAR_M := 16.0
var chart: Dictionary
var sources: Array
var shape: PlanetShape
var appearance: MiningAppearance
var result := {}
var triangles: Array = []

func _init(zone: MiningZone, patches: Array, natural: PlanetShape, climate: PlanetClimate, biomes: PlanetBiomes) -> void:
	chart = {"up": zone.up, "tx": zone.tangent_x, "ty": zone.tangent_y,
		"radius": zone.radius_m, "inner": Rect2(Vector2(zone.chunk_bounds.position) * 256, Vector2(zone.chunk_bounds.size) * 256)}
	chart.outer = chart.inner.grow(COLLAR_M)
	sources = patches
	shape = PlanetShape.new(natural.definition.duplicate(true), natural.geology)
	appearance = MiningAppearance.new(shape, climate, biomes)

func xy(p: Vector3) -> Vector2:
	var denom := MiningZone.dot64(p, chart.up)
	return Vector2(chart.radius * MiningZone.dot64(p, chart.tx) / denom, chart.radius * MiningZone.dot64(p, chart.ty) / denom)

static func unpack(arrays: Array, i: int) -> Dictionary:
	var v := {"p": arrays[Mesh.ARRAY_VERTEX][i], "n": arrays[Mesh.ARRAY_NORMAL][i],
		"uv": arrays[Mesh.ARRAY_TEX_UV][i], "c": arrays[Mesh.ARRAY_COLOR][i]}
	for pair in [["g", Mesh.ARRAY_CUSTOM0], ["a", Mesh.ARRAY_CUSTOM1], ["b", Mesh.ARRAY_CUSTOM2]]:
		var buffer = arrays[pair[1]]
		v[pair[0]] = Vector4(buffer[i * 4], buffer[i * 4 + 1], buffer[i * 4 + 2], buffer[i * 4 + 3]) if buffer != null else Vector4.ZERO
	return v

static func interpolate(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var v := {}
	for key in a:
		v[key] = a[key].lerp(b[key], t)
	return v

static func empty_arrays() -> Array:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	a[Mesh.ARRAY_TEX_UV] = PackedVector2Array()
	a[Mesh.ARRAY_COLOR] = PackedColorArray()
	for channel in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2]:
		a[channel] = PackedFloat32Array()
	a[Mesh.ARRAY_INDEX] = PackedInt32Array()
	return a

static func append_triangle(out: Array, a: Dictionary, b: Dictionary, c: Dictionary, orient_radially := true) -> void:
	# Clockwise front faces, consistent with the global and mining builders.
	var order := [a, b, c]
	if orient_radially and (b.p - a.p).cross(c.p - a.p).dot(a.p) > 0:
		order = [a, c, b]
	for v in order:
		out[Mesh.ARRAY_INDEX].append(out[Mesh.ARRAY_VERTEX].size())
		out[Mesh.ARRAY_VERTEX].append(v.p)
		out[Mesh.ARRAY_NORMAL].append(v.n.normalized())
		out[Mesh.ARRAY_TEX_UV].append(v.uv)
		out[Mesh.ARRAY_COLOR].append(v.c)
		for pair in [["g", Mesh.ARRAY_CUSTOM0], ["a", Mesh.ARRAY_CUSTOM1], ["b", Mesh.ARRAY_CUSTOM2]]:
			for k in range(4):
				out[pair[1]].append(v[pair[0]][k])

func signed_plane(p: Vector3, axis: int, bound: float, sign_value: float) -> float:
	var tangent: Vector3 = chart.tx if axis == 0 else chart.ty
	return sign_value * (chart.radius * MiningZone.dot64(p, tangent) - bound * MiningZone.dot64(p, chart.up))

func clip(poly: Array, plane: Array, keep_inside: bool) -> Array:
	var out := []
	if poly.is_empty():
		return out
	var a: Dictionary = poly[-1]
	var da := signed_plane(a.p, plane[0], plane[1], plane[2])
	for b: Dictionary in poly:
		var db := signed_plane(b.p, plane[0], plane[1], plane[2])
		var inside_a := da >= 0 if keep_inside else da <= 0
		var inside_b := db >= 0 if keep_inside else db <= 0
		if inside_a != inside_b:
			out.append(interpolate(a, b, da / (da - db)))
		if inside_b:
			out.append(b)
		a = b
		da = db
	return out

func build() -> void:
	var start := Time.get_ticks_usec()
	var outer: Rect2 = chart.outer
	var planes := [[0, outer.position.x, 1.0], [0, outer.end.x, -1.0], [1, outer.position.y, 1.0], [1, outer.end.y, -1.0]]
	var clipped := []
	for source: Dictionary in sources:
		# Recreate the captured leaf through the SAME deterministic global builder.
		# This avoids GPU readback stalls and retaining arrays for the entire planet.
		var builder := PlanetChunkBuilder.new(shape.definition, source.face, source.depth,
			source.cell, source.resolution, shape.geology, appearance.climate, appearance.biomes)
		builder.build()
		var arrays: Array = builder.result.arrays
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var out := empty_arrays()
		for i in range(0, indices.size(), 3):
			var tri := [unpack(arrays, indices[i]), unpack(arrays, indices[i + 1]), unpack(arrays, indices[i + 2])]
			if i < source.surface_indices:
				triangles.append(tri)
			var remaining := tri
			for plane in planes:
				var outside := clip(remaining, plane, false)
				for j in range(1, outside.size() - 1):
					append_triangle(out, outside[0], outside[j], outside[j + 1], false)
				remaining = clip(remaining, plane, true)
				if remaining.is_empty():
					break
		clipped.append({"key": source.key, "arrays": out})
	var ring := empty_arrays()
	var inner: Rect2 = chart.inner
	var corners_i := [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]
	var corners_o := [outer.position, Vector2(outer.end.x, outer.position.y), outer.end, Vector2(outer.position.x, outer.end.y)]
	var valid := true
	var outer_count := 0
	for side in range(4):
		var edge := outer_edge(corners_o[side], corners_o[(side + 1) % 4])
		if edge.size() < 2 or edge[0].t > 0.00001 or edge[-1].t < 0.99999:
			valid = false
			continue
		outer_count += edge.size()
		var inside := []
		var count := roundi(corners_i[side].distance_to(corners_i[(side + 1) % 4]) / 2.0)
		for i in range(count + 1):
			var t := float(i) / count
			inside.append({"t": t, "v": natural_vertex(corners_i[side].lerp(corners_i[(side + 1) % 4], t))})
		var a := 0
		var b := 0
		while a < inside.size() - 1 or b < edge.size() - 1:
			if b == edge.size() - 1 or (a < inside.size() - 1 and inside[a + 1].t <= edge[b + 1].t):
				append_triangle(ring, inside[a].v, edge[b].v, inside[a + 1].v)
				a += 1
			else:
				append_triangle(ring, inside[a].v, edge[b].v, edge[b + 1].v)
				b += 1
	result = {"clipped": clipped, "ring": ring, "faces": MiningBuildJob.collision_faces(ring),
		"valid": valid, "outer_vertices": outer_count, "started_usec": start, "ended_usec": Time.get_ticks_usec(),
		"build_ms": (Time.get_ticks_usec() - start) / 1000.0}

func natural_vertex(local: Vector2) -> Dictionary:
	var d: Vector3 = (chart.up + chart.tx * (local.x / chart.radius) + chart.ty * (local.y / chart.radius)).normalized()
	var surface := shape.sample_components(d)
	var p: Vector3 = d * (chart.radius + surface.x)
	var dx := natural_position(local + Vector2(2, 0)) - natural_position(local - Vector2(2, 0))
	var dy := natural_position(local + Vector2(0, 2)) - natural_position(local - Vector2(0, 2))
	var n := dx.cross(dy).normalized()
	var v := appearance.sample(d, surface, n)
	v.p = p
	v.n = n
	v.uv = local
	return v

func natural_position(local: Vector2) -> Vector3:
	var d: Vector3 = (chart.up + chart.tx * (local.x / chart.radius) + chart.ty * (local.y / chart.radius)).normalized()
	return d * (chart.radius + shape.sample_base_height(d))

func outer_edge(a: Vector2, b: Vector2) -> Array:
	var points := []
	var along := b - a
	for tri: Array in triangles:
		var uv := [xy(tri[0].p), xy(tri[1].p), xy(tri[2].p)]
		for k in range(3):
			var hit = Geometry2D.segment_intersects_segment(a, b, uv[k], uv[(k + 1) % 3])
			if hit != null:
				var t: float = clampf((hit - a).dot(along) / along.length_squared(), 0, 1)
				points.append({"t": t, "v": project_triangle(a.lerp(b, t), tri, uv)})
		for end in [0.0, 1.0]:
			var p := a.lerp(b, end)
			if Geometry2D.is_point_in_polygon(p, PackedVector2Array(uv)):
				points.append({"t": end, "v": project_triangle(p, tri, uv)})
	points.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return p.t < q.t)
	var unique := []
	for p: Dictionary in points:
		if unique.is_empty() or p.t - unique[-1].t > 0.000001:
			unique.append(p)
	return unique

func project_triangle(p: Vector2, tri: Array, uv: Array) -> Dictionary:
	var det: float = (uv[1] - uv[0]).cross(uv[2] - uv[0])
	var b: float = (p - uv[0]).cross(uv[2] - uv[0]) / det
	var c: float = (uv[1] - uv[0]).cross(p - uv[0]) / det
	# Perspective correction: affine chart barycentrics are not 3D barycentrics.
	var w := Vector3((1 - b - c) / MiningZone.dot64(tri[0].p, chart.up), b / MiningZone.dot64(tri[1].p, chart.up), c / MiningZone.dot64(tri[2].p, chart.up))
	w /= w.x + w.y + w.z
	var v := {}
	for key in tri[0]:
		v[key] = tri[0][key] * w.x + tri[1][key] * w.y + tri[2][key] * w.z
	return v
