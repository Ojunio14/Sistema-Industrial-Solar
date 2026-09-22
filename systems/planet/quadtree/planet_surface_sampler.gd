class_name PlanetSurfaceSampler
extends RefCounted

var tree: PlanetQuadtree
var radius: float
var cache: Dictionary = {}
var geometry: Dictionary = {}
var generated_count := 0

func _init(p_tree: PlanetQuadtree, p_radius: float, p_geometry: Dictionary = {}) -> void:
	tree = p_tree
	radius = p_radius
	geometry = p_geometry

func source(patch: PlanetPatch) -> Dictionary:
	var key := patch.id.stable_key()
	if not cache.has(key):
		var mask := tree.stitch_mask(patch.id)
		if not geometry.has(key):
			generated_count += 1
		cache[key] = PlanetPatchMesh.with_mask(geometry[key], mask) if geometry.has(key) else PlanetPatchMesh.generate(patch.id, radius, mask)
	return cache[key]

func sample(face: int, uv: Vector2) -> Vector3:
	var patch := tree.find_leaf(face, uv)
	var bounds := patch.id.get_uv_bounds()
	return PlanetPatchMesh.sample(source(patch), (uv - bounds.position) / bounds.size)

func prepare(fine: Dictionary) -> void:
	var context := begin_prepare(fine)
	advance_prepare(fine, context, PlanetPatchMesh.WIDTH * PlanetPatchMesh.WIDTH)

func begin_prepare(fine: Dictionary) -> Dictionary:
	# Packed arrays fetched from a Dictionary can alias the immutable geometry.
	# The morph destination must own its writable buffer.
	fine.from = fine.vertices.duplicate()
	var id: PatchId = fine.id
	var bounds := id.get_uv_bounds()
	# A fine patch is contained in ONE coarse leaf. Shared boundary values can
	# be sampled on that leaf, without resolving a neighbor for every vertex.
	var coarse := tree.find_leaf(id.face, bounds.get_center())
	var coarse_bounds := coarse.id.get_uv_bounds()
	assert(coarse.id.level <= id.level)
	var data := source(coarse)
	var difference := id.level - coarse.id.level
	var weights := PlanetPatchMesh.stencil(data.mask, -1 if difference == 0 else id.get_quadrant()) if difference <= 1 else {}
	return {"source": data, "stencil": weights, "offset": (bounds.position - coarse_bounds.position) / coarse_bounds.size,
		"scale": bounds.size / coarse_bounds.size, "next_vertex": 0}

func advance_prepare(fine: Dictionary, context: Dictionary, count: int) -> bool:
	var positions: PackedVector3Array = fine.from
	var uv: PackedVector2Array = fine.uv
	var data: Dictionary = context.source
	var offset: Vector2 = context.offset
	var scale: Vector2 = context.scale
	var stencil: Dictionary = context.stencil
	var end := mini(positions.size(), int(context.next_vertex) + count)
	if stencil.is_empty():
		for i in range(context.next_vertex, end):
			positions[i] = PlanetPatchMesh.sample(data, offset + uv[i] * scale)
	else:
		var indices: PackedInt32Array = stencil.indices
		var weights: PackedVector3Array = stencil.weights
		var ready: PackedByteArray = stencil.ready
		var vertices: PackedVector3Array = data.vertices
		for i in range(context.next_vertex, end):
			if ready[i] == 0:
				var interpolation := PlanetPatchMesh.sample_weights(data.mask, offset + uv[i] * scale)
				for component in range(3):
					indices[i * 3 + component] = interpolation[component]
				weights[i] = Vector3(interpolation[3], interpolation[4], interpolation[5])
				ready[i] = 1
			var weight := weights[i]
			positions[i] = vertices[indices[i * 3]] * weight.x + vertices[indices[i * 3 + 1]] * weight.y + vertices[indices[i * 3 + 2]] * weight.z
		stencil.indices = indices
		stencil.weights = weights
		stencil.ready = ready
	fine.from = positions
	context.next_vertex = end
	return end == positions.size()
