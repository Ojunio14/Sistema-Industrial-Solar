class_name PlanetPatch
extends RefCounted

var id: PatchId
var children: Array[PlanetPatch] = []

func _init(p_id: PatchId) -> void:
	id = p_id

func is_leaf() -> bool:
	return children.is_empty()

