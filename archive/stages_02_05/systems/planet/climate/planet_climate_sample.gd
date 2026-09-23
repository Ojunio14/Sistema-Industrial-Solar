class_name PlanetClimateSample
extends RefCounted
## Caller-owned result. climate = Celsius, humidity, ocean influence, precipitation.
## weights remain normalized across the ten terrestrial biome families.
var climate := Vector4.ZERO
var rain_shadow := 0.0
var dominant := -1
var secondary := -1
var top_pair_mix := 1.0
var weights := PackedFloat32Array()

func _init() -> void:
	weights.resize(10)
