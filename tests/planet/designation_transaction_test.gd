extends "res://tests/planet/designation_test.gd"

func drain() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while (not store.running.is_empty() or not store.queued.is_empty()) and Time.get_ticks_msec() < deadline:
		store.advance_transactions()
		await process_frame
	expect(store.running.is_empty() and store.queued.is_empty(), "Worker settles within bound")

func _run() -> void:
	var definition: PlanetDefinition = load("res://systems/planet/surface/data/test_planet_100km.tres")
	terrain = PlanetEditableTerrain.new(PlanetShape.new(definition, PlanetGeology.new(definition)))
	zone = terrain.create_zone("transactions", Vector3(1, 0.4, 1).normalized())
	for coord in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i.ZERO]:
		zone.activate_chunk(coord)
	store = TerrainDesignationStore.new(terrain, TerrainLevelDatum.new(roundf(terrain.sample_natural_height(zone.up)) - 10, 1))
	var plan := platform(Rect2i(-16, -16, 32, 32), 10)
	expect(store.confirm(plan), "Confirmed transactional plan")
	var job := evaluate(plan)
	var clock := zone._clock
	expect(store.queue_apply([job]).ok, "First request queues")
	store.advance_transactions()
	expect(zone._clock == clock, "Worker cannot mutate live terrain")
	expect(store.queue_apply([job]).ok, "Second request supersedes first")
	await drain()
	expect(store.rejected_transactions == 1, "Superseded worker result rejected")
	expect(zone._clock == clock + 1, "Exactly one data revision for entire transaction")
	for chunk: MiningChunk in zone._chunks.values():
		expect(chunk.revision == zone._clock, "Every affected chunk has same revision")
	job = evaluate(plan)
	expect(store.queue_apply([job]).ok, "Queue a result that will become stale")
	store.advance_transactions()
	zone._write_node(Vector2i.ZERO, zone.read_node(Vector2i.ZERO) + 1)
	clock = zone._clock
	await drain()
	expect(store.rejected_transactions == 2 and zone._clock == clock, "Concurrent edit rejects stale worker atomically")
	job = evaluate(plan)
	expect(store.queue_apply([job]).ok, "Queue before plan mutation")
	store.advance_transactions()
	store.remove(plan.id)
	await drain()
	expect(store.rejected_transactions == 3 and zone._clock == clock, "Plan mutation rejects stale result")
	# Interrupted preview progress must survive coalesced drag events.
	plan.id = 0
	plan.rect = Rect2i(10, 10, 16, 16)
	job = store.begin_evaluation(plan)
	store.advance_evaluation(job, 50, 100)
	var done_nodes: int = job.nodes.size()
	plan.rect.size.x = 17
	var next := store.begin_evaluation(plan)
	expect(next.nodes.size() == done_nodes, "Partial node work survives next mouse event")
	while not store.advance_evaluation(next):
		await process_frame
	expect(next.cells.size() == 272 and next.nodes.size() == 306, "Coalesced rectangle has exact complete topology")
	# Published evaluation uses a detached worker and cannot race live edits.
	var natural := PackedFloat32Array()
	natural.resize(129 * 129)
	natural.fill(100)
	var heights := natural.duplicate()
	heights.fill(105)
	var vertices := PackedVector3Array()
	vertices.resize(129 * 129)
	terrain.published_chunks[zone.id] = {}
	for coord in zone._chunks:
		terrain.published_chunks[zone.id][coord] = {"revision": zone._chunks[coord].revision, "natural": natural, "heights": heights, "vertices": vertices}
	store.datum = TerrainLevelDatum.new(95, 1)
	store.evaluation_cache.clear()
	job = store.begin_evaluation(plan)
	expect(not store.advance_evaluation(job) and not store.evaluation_running.is_empty(), "Published selection starts worker instead of blocking frame")
	expect(job.nodes.is_empty(), "Detached worker never mutates UI dictionaries")
	zone._write_node(Vector2i(12, 12), zone.read_node(Vector2i(12, 12)) + 1)
	while not store.advance_evaluation(job):
		await process_frame
	expect(not job.error.is_empty(), "Live change invalidates detached evaluation")
	job = store.begin_evaluation(plan)
	while not store.advance_evaluation(job):
		await process_frame
	expect(job.current_min == 10 and job.current_max == 10, "Current comes from published snapshot while new data is pending")
	expect(job.in_progress == job.cells.size(), "Data/published revision mismatch remains pending")
	var queries := store.natural_queries
	plan.start_level = 11
	job = store.begin_evaluation(plan)
	while not store.advance_evaluation(job):
		await process_frame
	expect(store.natural_queries == queries and job.current_min == 10, "Target change reuses cached Current in worker")
	store.finish_workers()
	print("DESIGNATION_TRANSACTIONS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
