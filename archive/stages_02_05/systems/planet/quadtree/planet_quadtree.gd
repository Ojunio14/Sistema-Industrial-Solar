class_name PlanetQuadtree
extends RefCounted

var roots: Array[PlanetPatch] = []
var nodes: Dictionary = {}
var leaves: Dictionary = {}
var _mask_cache: Dictionary = {}

func _init() -> void:
	for face in range(6):
		var patch := PlanetPatch.new(PatchId.root(face))
		roots.append(patch)
		nodes[patch.id.stable_key()] = patch
		leaves[patch.id.stable_key()] = patch

func copy_tree() -> PlanetQuadtree:
	var result := PlanetQuadtree.new()
	var internals: Array[PlanetPatch] = []
	for patch: PlanetPatch in nodes.values():
		if not patch.is_leaf():
			internals.append(patch)
	internals.sort_custom(func(a: PlanetPatch, b: PlanetPatch) -> bool: return a.id.level < b.id.level)
	for patch in internals:
		result._split_unchecked(patch.id)
	return result

func find_leaf(face: int, uv: Vector2) -> PlanetPatch:
	if not PlanetMath.is_valid_face(face) or not PlanetMath.is_valid_uv(uv):
		return null
	var patch := roots[face]
	while not patch.is_leaf():
		var center := patch.id.get_uv_bounds().get_center()
		var quadrant := int(uv.x >= center.x) + 2 * int(uv.y >= center.y)
		patch = patch.children[quadrant]
	return patch

func active_leaves() -> Array[PlanetPatch]:
	var result: Array[PlanetPatch] = []
	# Keys already exist: do not format PatchId strings inside O(n log n) callbacks.
	var keys: Array = leaves.keys()
	keys.sort()
	for key in keys:
		result.append(leaves[key])
	return result

# Descend only the neighbor's touching edge; never scan the entire planet.
func neighbors(id: PatchId, edge: int) -> Array[PlanetPatch]:
	var target := PlanetTopology.get_neighbor_patch(id, edge)
	var touching := edge ^ 1
	if target.face != id.face:
		touching = PlanetTopology.get_edge_transition(id.face, edge).neighbor_edge
	var ancestor := target
	while not nodes.has(ancestor.stable_key()):
		ancestor = ancestor.get_parent_id()
	var result: Array[PlanetPatch] = []
	_collect_edge(nodes[ancestor.stable_key()], touching, result)
	return result

func _collect_edge(patch: PlanetPatch, edge: int, result: Array[PlanetPatch]) -> void:
	if patch.is_leaf():
		result.append(patch)
		return
	var quadrants: Array = [[0, 2], [1, 3], [0, 1], [2, 3]][edge]
	for quadrant: int in quadrants:
		_collect_edge(patch.children[quadrant], edge, result)

# Return a complete dependency-ordered closure, or nothing if budget cannot fit it.
func split_plan(id: PatchId, budget: int, max_level: int) -> Array[PatchId]:
	var result: Array[PatchId] = []
	var visited := {}
	if not leaves.has(id.stable_key()) or id.level >= mini(max_level, PatchId.MAX_LEVEL):
		return result
	_plan_split(id, result, visited)
	if result.size() > budget:
		return []
	return result

func _plan_split(id: PatchId, result: Array[PatchId], visited: Dictionary) -> void:
	if visited.has(id.stable_key()):
		return
	visited[id.stable_key()] = true
	for edge in range(4):
		for neighbor in neighbors(id, edge):
			if neighbor.id.level < id.level:
				_plan_split(neighbor.id, result, visited)
	result.append(id)

func split(id: PatchId, budget: int = 8, max_level: int = 6) -> int:
	var plan := split_plan(id, budget, max_level)
	for planned in plan:
		_split_unchecked(planned)
	return plan.size()

func _split_unchecked(id: PatchId) -> void:
	_mask_cache.clear()
	var patch: PlanetPatch = nodes[id.stable_key()]
	assert(patch.is_leaf() and id.level < PatchId.MAX_LEVEL)
	leaves.erase(id.stable_key())
	for child_id: PatchId in id.get_children_ids():
		var child := PlanetPatch.new(child_id)
		patch.children.append(child)
		nodes[child_id.stable_key()] = child
		leaves[child_id.stable_key()] = child

func can_merge(id: PatchId) -> bool:
	if not nodes.has(id.stable_key()):
		return false
	var patch: PlanetPatch = nodes[id.stable_key()]
	if patch.is_leaf():
		return false
	for child in patch.children:
		if not child.is_leaf():
			return false
	for edge in range(4):
		for neighbor in neighbors(id, edge):
			if neighbor.id.level > id.level + 1:
				return false
	return true

func merge(id: PatchId) -> bool:
	if not can_merge(id):
		return false
	_mask_cache.clear()
	var patch: PlanetPatch = nodes[id.stable_key()]
	for child in patch.children:
		nodes.erase(child.id.stable_key())
		leaves.erase(child.id.stable_key())
	patch.children.clear()
	leaves[id.stable_key()] = patch
	return true

func stitch_mask(id: PatchId) -> int:
	var key := id.stable_key()
	if _mask_cache.has(key):
		return _mask_cache[key]
	var mask := 0
	for edge in range(4):
		for neighbor in neighbors(id, edge):
			if neighbor.id.level < id.level:
				mask |= 1 << edge
	_mask_cache[key] = mask
	return mask

func is_balanced() -> bool:
	for patch: PlanetPatch in leaves.values():
		if not validate_leaf(patch.id):
			return false
	return true

# Also fills the mask from the same traversal, on an immutable transaction tree.
func validate_leaf(id: PatchId) -> bool:
	var mask := 0
	for edge in range(4):
		for neighbor in neighbors(id, edge):
			if absi(id.level - neighbor.id.level) > 1:
				return false
			if neighbor.id.level < id.level:
				mask |= 1 << edge
	_mask_cache[id.stable_key()] = mask
	return true
