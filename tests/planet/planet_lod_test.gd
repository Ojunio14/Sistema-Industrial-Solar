extends SceneTree

var failures: Array[String] = []
var manager: PlanetLODManager
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_mesh_seams()
	manager = PlanetLODManager.new()
	manager.chunk_resolution = 9
	manager.max_depth = 4
	manager.max_resident_chunks = 126
	manager.max_cached_chunks = 24
	manager.upload_budget_ms = 10.0
	root.add_child(manager)
	manager.set_process(false)
	var definition := PlanetDefinition.new()
	manager.configure(definition)
	await _settle(Vector3(1.0e8, 0, 0))
	_expect(manager.get_stats().visible == 6, "As seis raízes devem cobrir o planeta distante.")
	var near := Vector3(1, 0.2, 0.3).normalized() * 50100.0
	await _settle(near)
	var near_stats := manager.get_stats()
	print("NEAR ", near_stats)
	_expect(near_stats.depth > 0, "Aproximação deve aumentar o LOD.")
	_expect(near_stats.depth <= manager.max_depth, "Profundidade máxima respeitada.")
	_expect(near_stats.resident <= manager.max_resident_chunks, "Orçamento de nós respeitado.")
	_test_projection_and_hysteresis()
	# Viajar por uma borda e um canto do cubo.
	await _settle(Vector3(1, 1, 0).normalized() * 50100.0)
	await _settle(Vector3(1, 1, 1).normalized() * 50100.0)
	await _settle(Vector3(1.0e8, 0, 0))
	_expect(manager.get_stats().resident == 6, "Afastamento deve liberar todos os descendentes.")
	_expect(manager.get_stats().visible == 6, "Merge preserva as seis faces.")
	_expect(manager.get_stats().cached <= manager.max_cached_chunks, "Cache deve ser limitado.")
	# Voltar exatamente à última região deve reutilizar parte das malhas.
	await _settle(Vector3(1, 1, 1).normalized() * 50100.0)
	_expect(manager.cache_hits > 0, "Viagem de retorno deve ter acertos no cache.")
	await _settle(Vector3(1.0e8, 0, 0))
	# Cancelar filhos enquanto jobs existem, trocar seed e rejeitar revisão antiga.
	manager.select_lod(near, 720.0)
	manager._dispatch_jobs()
	_expect(manager.get_stats().jobs > 0, "Cenário de invalidação precisa de jobs em voo.")
	var old_revision := manager.revision
	definition.seed += 42
	manager.configure(definition)
	await _settle(Vector3(1.0e8, 0, 0))
	_expect(manager.revision == old_revision + 1, "Mudança da base incrementa revisão.")
	_expect(manager.discarded_jobs > 0, "Jobs antigos devem ser descartados.")
	_expect(manager.get_stats().visible == 6, "Revisão nova deve reconstruir as seis raízes.")
	print("FINAL ", manager.get_stats())
	manager.free()
	# Encerrar gerenciador ocupado aguarda workers e não acessa nós liberados.
	var closing := PlanetLODManager.new()
	root.add_child(closing)
	closing.set_process(false)
	closing.configure(definition)
	closing._dispatch_jobs()
	closing.free()
	if failures.is_empty():
		print("Planet LOD: PASS (%d verificações)." % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _settle(eye: Vector3) -> void:
	var stable := 0
	for frame in range(2500):
		manager._poll_jobs()
		manager.select_lod(eye, 720.0)
		manager._dispatch_jobs()
		var stats := manager.get_stats()
		_expect(stats.jobs <= manager.max_worker_jobs, "Limite de workers excedido.")
		_expect(manager._uploads_this_frame <= manager.max_uploads_per_frame, "Uploads de jobs e cache precisam compartilhar o limite por frame.")
		if stats.visible >= 6:
			for node in manager.roots:
				_expect(_covered(node), "Uma transição deixou uma região sem cobertura.")
		stable = stable + 1 if stats.jobs == 0 and stats.queued == 0 else 0
		if stable >= 3:
			return
		await create_timer(0.003).timeout
	_expect(false, "LOD não estabilizou dentro do limite de quadros.")


func _covered(node: QuadtreeNode) -> bool:
	if not node.is_split:
		return node.mesh_instance != null and node.mesh_instance.visible
	if node.mesh_instance.visible or node.children.size() != 4:
		return false
	for child in node.children:
		if not _covered(child):
			return false
	return true


func _test_projection_and_hysteresis() -> void:
	var node := manager.roots[0]
	var eye := Vector3(100000, 0, 0)
	var small := PlanetLODManager.projected_error(node, eye, 500.0)
	var large := PlanetLODManager.projected_error(node, eye, 1000.0)
	_expect(is_equal_approx(large, small * 2.0), "Resolução/FOV devem alterar o erro projetado.")
	var before := node.is_split
	# Projeção ortográfica permite testar exatamente dentro da banda de histerese.
	var band := manager.split_error_pixels * 0.8 / node.error_m
	manager._select(node, eye, 500.0, band)
	_expect(node.is_split == before, "Dentro da banda de histerese o estado deve ser preservado.")


func _test_mesh_seams() -> void:
	var definition := PlanetDefinition.new()
	var resolution := 9
	var meshes: Array[Dictionary] = []
	for face in range(6):
		var builder := PlanetChunkBuilder.new(definition, face, 0, Vector2i.ZERO, resolution)
		builder.build()
		meshes.append(builder.result)
		var arrays: Array = builder.result.arrays
		_expect(arrays[Mesh.ARRAY_VERTEX].size() == resolution * resolution + 4 * resolution, "Quatro saias devem estar presentes.")
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(resolution * resolution):
			_expect(normals[i].dot(positions[i].normalized()) > 0.0, "Normais precisam apontar para fora.")
	# Cada vértice de borda deve ter correspondência em outra face, incluindo cantos.
	for face in range(6):
		var a: Array = meshes[face].arrays
		for y in range(resolution):
			for x in range(resolution):
				if x != 0 and x != resolution - 1 and y != 0 and y != resolution - 1:
					continue
				var i := x + y * resolution
				var matches := 0
				for other in range(6):
					if other == face:
						continue
					var b: Array = meshes[other].arrays
					for j in range(resolution * resolution):
						if a[Mesh.ARRAY_VERTEX][i].distance_to(b[Mesh.ARRAY_VERTEX][j]) < 0.003:
							matches += 1
							_expect(a[Mesh.ARRAY_NORMAL][i].distance_to(b[Mesh.ARRAY_NORMAL][j]) < 0.003, "Normais não coincidem entre faces.")
				_expect(matches >= 1, "Borda sem correspondente em outra face.")
	# Amostras coincidentes de pai e filho têm posição e normal iguais.
	var child := PlanetChunkBuilder.new(definition, 0, 1, Vector2i.ZERO, resolution)
	child.build()
	var parent_arrays: Array = meshes[0].arrays
	var child_arrays: Array = child.result.arrays
	for y in range(0, resolution, 2):
		for x in range(0, resolution, 2):
			var i := x + y * resolution
			var j := x / 2 + (y / 2) * resolution
			_expect(child_arrays[Mesh.ARRAY_VERTEX][i].distance_to(parent_arrays[Mesh.ARRAY_VERTEX][j]) < 0.003, "Vértices compartilhados de LODs não coincidem.")
			_expect(child_arrays[Mesh.ARRAY_NORMAL][i].distance_to(parent_arrays[Mesh.ARRAY_NORMAL][j]) < 0.003, "Normais compartilhadas de LODs não coincidem.")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message):
		failures.append(message)
