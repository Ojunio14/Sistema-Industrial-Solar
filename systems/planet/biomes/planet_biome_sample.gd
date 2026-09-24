class_name PlanetBiomeSample
extends RefCounted
## Dez pesos terrestres normalizados. Na água: IDs -1 e pesos zerados.
var dominant := -1
var secondary := -1
var dominant_weight := 0.0
var secondary_weight := 0.0
var top_pair_mix := 0.5
var regional_slope := 0.0
var weights := PackedFloat32Array()

func _init() -> void:
	weights.resize(10)

func is_water() -> bool:
	return dominant < 0
