class_name TerrainDesignation
extends RefCounted
## A plan, never a terrain mesh. Integer anchors; ramp fractions derive from grid
## coordinates each time, without accumulating floating-point level increments.
enum Kind { PLATFORM, RAMP }
enum Operation { CUT_AND_FILL, CUT_ONLY, FILL_ONLY }
enum HeightState { CUT_REQUIRED, AT_TARGET, FILL_REQUIRED }
enum WorkState { PLANNED, IN_PROGRESS, COMPLETE }
var id := 0
var zone_id := ""
var rect := Rect2i()
var kind := Kind.PLATFORM
var start_level := 0
var end_level := 0
var axis := 0
var reverse := false
var operation := Operation.CUT_AND_FILL
var started := false

func level_at(grid_point: Vector2) -> float:
	if kind == Kind.PLATFORM:
		return float(start_level)
	var t := clampf((grid_point[axis] - rect.position[axis]) / float(rect.size[axis]), 0.0, 1.0)
	if reverse:
		t = 1.0 - t
	return lerpf(float(start_level), float(end_level), t)

func planned_level(cell: Vector2i) -> float:
	return level_at(Vector2(cell) + Vector2(0.5, 0.5))

func target_height(grid_point: Vector2, datum: TerrainLevelDatum) -> float:
	return datum.height(level_at(grid_point))

func grade_percent(datum: TerrainLevelDatum) -> float:
	return 0.0 if kind == Kind.PLATFORM else absf(end_level - start_level) * datum.level_step / (rect.size[axis] * MiningChunk.CELL_M) * 100.0

func duplicate_plan() -> TerrainDesignation:
	var copy := TerrainDesignation.new()
	for key in ["id", "zone_id", "rect", "kind", "start_level", "end_level", "axis", "reverse", "operation", "started"]:
		copy.set(key, get(key))
	return copy
