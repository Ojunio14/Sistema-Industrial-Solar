extends SceneTree
var checks := 0
var failures := 0
var terrain: PlanetEditableTerrain
var zone: MiningZone
var store: TerrainDesignationStore

func _initialize() -> void:
	_run.call_deferred()

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 35:
			printerr("TEST_FAILED " + message)

func platform(rect: Rect2i, level: int) -> TerrainDesignation:
	var plan := TerrainDesignation.new()
	plan.zone_id = zone.id
	plan.rect = rect
	plan.start_level = level
	return plan

func evaluate(plan: TerrainDesignation) -> Dictionary:
	var job := store.begin_evaluation(plan)
	while not store.advance_evaluation(job):
		pass
	return job

func evaluate_all() -> Array:
	var jobs: Array = []
	for plan in store.plans:
		jobs.append(evaluate(plan))
	return jobs

func _run() -> void:
	var definition: PlanetDefinition = load("res://systems/planet/surface/data/test_planet_100km.tres")
	terrain = PlanetEditableTerrain.new(PlanetShape.new(definition, PlanetGeology.new(definition)))
	zone = terrain.create_zone("levels", Vector3(1, 0.4, 1).normalized())
	for y in [-1, 0]:
		for x in [-1, 0]:
			zone.activate_chunk(Vector2i(x, y))
	zone.visual_guard_cells = 2
	var origin := roundf(terrain.sample_natural_height(zone.up)) - 7
	store = TerrainDesignationStore.new(terrain, TerrainLevelDatum.new(origin, 1.0))
	var other := terrain.create_zone("other", -zone.up)
	var datum := TerrainLevelDatum.new(100, 0.25)
	expect(datum.height(-3) == 99.25 and datum.height(10) == 102.5, "Configurable origin, step and negative levels")
	for level in range(-10000, 10000, 7):
		expect(datum.height(level) == 100 + level * 0.25, "Levels derive directly, without cumulative drift")
	var same := platform(Rect2i(4, 4, 2, 2), 10)
	same.zone_id = other.id
	expect(same.target_height(Vector2(4, 4), store.datum) == platform(Rect2i(-8, -8, 2, 2), 10).target_height(Vector2(-8, -8), store.datum), "Level 10 is the same altitude across zones/selections")
	var a := platform(Rect2i(-12, -3, 6, 6), 10)
	var b := platform(Rect2i(6, -3, 6, 6), 5)
	expect(store.confirm(a) and store.confirm(b), "Two platforms planned")
	var ramp := platform(Rect2i(-6, -3, 12, 6), 0)
	ramp.kind = TerrainDesignation.Kind.RAMP
	var anchors := store.detect_ramp_anchors(ramp)
	expect(anchors == [10, 5], "Anchors detect entire neighboring platform edges")
	ramp.start_level = anchors[0]
	ramp.end_level = anchors[1]
	expect(is_equal_approx(ramp.grade_percent(store.datum), 100.0 * 5 / 24), "Grade uses vertical difference / horizontal length")
	expect(store.confirm(ramp), "Ramp can connect platforms")
	expect(zone.delta_bytes() == 0, "Planning and confirmation never edit terrain")
	for x in range(-6, 7):
		var target := ramp.target_height(Vector2(x, 0), store.datum)
		for y in range(-3, 4):
			expect(target == ramp.target_height(Vector2(x, y), store.datum), "Every transverse row shares its ramp target")
		if x < 6:
			expect(absf(target - ramp.target_height(Vector2(x + 1, 0), store.datum) - 5.0 / 12.0) < 0.00001, "Continuous ramp has no quantized stair steps")
	var bad := platform(Rect2i(-6, -3, 12, 6), 20)
	bad.kind = TerrainDesignation.Kind.RAMP
	bad.end_level = 0
	expect(not store.validate(bad).is_empty(), "Over-steep ramp rejected")
	bad = platform(Rect2i(30, 30, 65, 65), 10)
	expect(not store.validate(bad).is_empty(), "Large selection bounded")
	bad = platform(Rect2i(-127, -3, 2, 2), 10)
	expect(not store.validate(bad).is_empty(), "Protected zone boundary rejected")
	bad = a.duplicate_plan()
	bad.start_level = 11
	expect(not store.validate(bad).is_empty(), "Conflicting targets on shared edge rejected")
	var jobs := evaluate_all()
	var before: Array = []
	var cut := 0.0
	var fill := 0.0
	for job: Dictionary in jobs:
		expect(job.error.is_empty(), "Evaluation valid")
		cut += job.cut_m3
		fill += job.fill_m3
		for cell: Dictionary in job.cells:
			expect(is_equal_approx(cell.target_height, store.datum.height(cell.planned_level)), "Cell reports planned level, not natural height")
			before.append(cell.height_difference)
	expect(cut > 0 and fill > 0, "Irregular terrain exposes cut and fill separately")
	var sample_cell := Vector2i(-12, -3)
	var synthetic := {}
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
		var target := store.datum.height(10)
		synthetic[sample_cell + offset] = {"current": target, "target": target}
	synthetic[sample_cell].current += 1.0
	synthetic[sample_cell + Vector2i.ONE].current -= 1.0
	var mixed := store.cell_status(a, sample_cell, synthetic)
	expect(mixed.height_state == TerrainDesignation.HeightState.AT_TARGET and mixed.work_state != TerrainDesignation.WorkState.COMPLETE, "Centre at target cannot conceal unfinished irregular corners")
	expect(mixed.mixed_cut_fill and mixed.cut_m3 > 0 and mixed.fill_m3 > 0, "Mixed cell retains both cut and fill work")
	var invalid_ramp := platform(Rect2i(40, -10, 2, 2), 10)
	invalid_ramp.kind = TerrainDesignation.Kind.RAMP
	invalid_ramp.end_level = 0
	var invalid_job := evaluate(invalid_ramp)
	expect(not invalid_job.error.is_empty() and invalid_job.cells.size() == 4, "Invalid steep ramp still supplies visible preview cells")
	expect(not store.confirm(invalid_ramp), "Invalid visible preview cannot be confirmed")
	var partial := store.apply_evaluations(jobs, 0.25)
	expect(partial.ok, "Finite work step accepted without moving target")
	jobs = evaluate_all()
	var progress := 0
	for job: Dictionary in jobs:
		progress += job.in_progress
	expect(progress > 0, "IN_PROGRESS derived after partial work")
	expect(store.apply_evaluations(jobs).ok, "DEV APPLY to every own target")
	jobs = evaluate_all()
	for job: Dictionary in jobs:
		expect(job.complete == job.cells.size(), "COMPLETE requires all cell corners within tolerance")
		for node: Vector2i in job.nodes:
			expect(absf(job.nodes[node].current - job.nodes[node].target) < store.tolerance_m, "Shared target reached exactly within delta precision")
	var clock := zone._clock
	expect(store.apply_evaluations(jobs).ok, "Repeated DEV APPLY is idempotent")
	expect(zone._clock == clock, "Idempotent apply does not dirty chunks")
	expect(not store.apply_evaluations(jobs).ok, "Plan revision rejects stale evaluation")
	jobs = evaluate_all()
	terrain.set_node_delta(zone.id, Vector2i.ZERO, zone.read_node(Vector2i.ZERO) + 0.2)
	expect(not store.apply_evaluations(jobs).ok, "Terrain revision rejects stale evaluation")
	# Operation policy preserves target but never moves in the forbidden direction.
	var cut_only := platform(Rect2i(20, 20, 2, 2), 10)
	cut_only.operation = TerrainDesignation.Operation.CUT_ONLY
	expect(store.confirm(cut_only), "CUT_ONLY plan")
	var cut_job := evaluate(cut_only)
	var prior: float = cut_job.nodes[Vector2i(20, 20)].current
	expect(store.apply_evaluations([cut_job]).ok, "Apply cut-only")
	var cut_after := evaluate(cut_only)
	expect(cut_after.nodes[Vector2i(20, 20)].current <= prior + 0.00001, "CUT_ONLY cannot fill")
	var fill_only := platform(Rect2i(24, 24, 2, 2), 5)
	fill_only.operation = TerrainDesignation.Operation.FILL_ONLY
	expect(store.confirm(fill_only), "FILL_ONLY plan")
	var fill_job := evaluate(fill_only)
	prior = fill_job.nodes[Vector2i(24, 24)].current
	expect(store.apply_evaluations([fill_job]).ok, "Apply fill-only")
	expect(evaluate(fill_only).nodes[Vector2i(24, 24)].current >= prior - 0.00001, "FILL_ONLY cannot cut")
	var envelope := platform(Rect2i(30, 30, 2, 2), 10000)
	expect(store.confirm(envelope), "Planning can express work outside DEV envelope")
	clock = zone._clock
	expect(not store.apply_evaluations([evaluate(envelope)]).ok and zone._clock == clock, "Envelope failure leaves all deltas unchanged")
	var reverse := ramp.duplicate_plan()
	reverse.reverse = true
	reverse.start_level = 5
	reverse.end_level = 10
	expect(reverse.target_height(Vector2(-6, 0), store.datum) == ramp.target_height(Vector2(-6, 0), store.datum), "Reverse ramp preserves endpoint semantics")
	print("DESIGNATION_CONTRACT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
