class_name PlanetProfile
extends RefCounted

# Opt-in; no per-vertex timers or I/O. Times are microseconds, reset per update.
var enabled := false
var times: Dictionary = {}
var counts: Dictionary = {}

func stamp() -> int:
	return Time.get_ticks_usec() if enabled else 0

func begin() -> void:
	if enabled:
		times.clear()
		counts.clear()

func finish(key: StringName, start: int) -> void:
	if enabled:
		times[key] = int(times.get(key, 0)) + Time.get_ticks_usec() - start

func count(key: StringName, amount: int = 1) -> void:
	if enabled:
		counts[key] = int(counts.get(key, 0)) + amount
