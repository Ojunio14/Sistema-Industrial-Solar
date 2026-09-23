class_name PlanetFaceUV
extends RefCounted

var face: int
var uv: Vector2


func _init(p_face: int = -1, p_uv: Vector2 = Vector2.ZERO) -> void:
	face = p_face
	uv = p_uv


func is_equal(other: PlanetFaceUV, epsilon: float = 0.000001) -> bool:
	return other != null and face == other.face and uv.distance_to(other.uv) <= epsilon


func _to_string() -> String:
	return "PlanetFaceUV(face=%d, uv=%s)" % [face, uv]
