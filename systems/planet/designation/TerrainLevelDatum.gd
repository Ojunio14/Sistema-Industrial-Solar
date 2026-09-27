class_name TerrainLevelDatum
extends RefCounted
## Immutable planet-wide altitude datum, shared by every zone and designation.
## Changing the step/origin requires an explicit future migration of saved plans.
var _origin_height: float
var _level_step: float
var origin_height: float:
	get: return _origin_height
var level_step: float:
	get: return _level_step

func _init(origin := 0.0, step := 1.0) -> void:
	assert(is_finite(origin) and is_finite(step) and step > 0.0)
	_origin_height = origin
	_level_step = step

func height(level: float) -> float:
	return origin_height + level * level_step

func nearest_level(altitude: float) -> int:
	return roundi((altitude - origin_height) / level_step)
