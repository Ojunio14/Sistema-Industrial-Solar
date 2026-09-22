class_name PlanetEdgeTransition
extends RefCounted

var neighbor_face: int
var neighbor_edge: int
var is_reversed: bool


func _init(p_neighbor_face: int = -1, p_neighbor_edge: int = -1, p_is_reversed: bool = false) -> void:
	neighbor_face = p_neighbor_face
	neighbor_edge = p_neighbor_edge
	is_reversed = p_is_reversed


func _to_string() -> String:
	return "PlanetEdgeTransition(face=%d, edge=%d, reversed=%s)" % [
		neighbor_face,
		neighbor_edge,
		is_reversed,
	]
