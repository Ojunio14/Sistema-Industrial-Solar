extends SceneTree
## A protected ancestor must still let its unrelated descendants merge in orbit.
var failures := 0
var renderer: PlanetLODManager

func _initialize() -> void:
	_run.call_deferred()

func node(depth: int, cell: Vector2i) -> QuadtreeNode:
	var item := QuadtreeNode.new(0, depth, cell)
	item.mesh_instance = MeshInstance3D.new()
	renderer.add_child(item.mesh_instance)
	renderer._nodes[item.key] = item
	return item

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("TEST_FAILED " + message)

func _run() -> void:
	renderer = PlanetLODManager.new()
	root.add_child(renderer)
	renderer.set_process(false)
	renderer.max_cached_chunks = 0
	var parent := node(0, Vector2i.ZERO)
	renderer.roots.append(parent)
	parent.is_split = true
	for y in range(2):
		for x in range(2):
			parent.children.append(node(1, Vector2i(x, y)))
	var pinned := parent.children[0]
	var unprotected := parent.children[1]
	unprotected.is_split = true
	for y in range(2):
		for x in range(2):
			unprotected.children.append(node(2, unprotected.cell * 2 + Vector2i(x, y)))
	renderer.mining_pins[pinned.key] = "test-zone"
	renderer.mining_protected[parent.key] = true
	renderer.mining_protected[pinned.key] = true
	# Zero-size bounds and error simulate a leaf insignificant in an orbital view.
	# Orthographic input avoids depending on a natural generator in this LOD test.
	renderer._select(parent, Vector3.ZERO, 0.0, 1.0)
	expect(parent.is_split and pinned.alive and pinned.mesh_instance.visible, "Pinned coverage remains visible")
	expect(not unprotected.is_split and unprotected.children.is_empty(), "Unrelated branch merges below protected ancestor")
	expect(renderer._nodes.size() == 5, "Only the protected topology remains resident")
	renderer.release_mining_pins("test-zone")
	renderer._select(parent, Vector3.ZERO, 0.0, 1.0)
	expect(not parent.is_split and renderer._nodes.size() == 1, "Ordinary merge resumes after deactivation")
	print("MINING_LOD_OWNERSHIP checks=4 failures=", failures)
	renderer.queue_free()
	await process_frame
	quit(1 if failures else 0)
