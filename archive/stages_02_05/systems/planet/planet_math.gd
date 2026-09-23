class_name PlanetMath
extends RefCounted

enum Face {
	POSITIVE_X,
	NEGATIVE_X,
	POSITIVE_Y,
	NEGATIVE_Y,
	POSITIVE_Z,
	NEGATIVE_Z,
}

enum Edge {
	LEFT,
	RIGHT,
	TOP,
	BOTTOM,
}

const FACE_COUNT := 6
const EDGE_COUNT := 4

# Every face basis is orthonormal and right-handed: U × V = normal.
const FACE_NORMALS := [
	Vector3(1.0, 0.0, 0.0),
	Vector3(-1.0, 0.0, 0.0),
	Vector3(0.0, 1.0, 0.0),
	Vector3(0.0, -1.0, 0.0),
	Vector3(0.0, 0.0, 1.0),
	Vector3(0.0, 0.0, -1.0),
]

const FACE_U_AXES := [
	Vector3(0.0, 0.0, -1.0),
	Vector3(0.0, 0.0, 1.0),
	Vector3(1.0, 0.0, 0.0),
	Vector3(1.0, 0.0, 0.0),
	Vector3(1.0, 0.0, 0.0),
	Vector3(-1.0, 0.0, 0.0),
]

const FACE_V_AXES := [
	Vector3(0.0, 1.0, 0.0),
	Vector3(0.0, 1.0, 0.0),
	Vector3(0.0, 0.0, -1.0),
	Vector3(0.0, 0.0, 1.0),
	Vector3(0.0, 1.0, 0.0),
	Vector3(0.0, 1.0, 0.0),
]

const FACE_NAMES := [
	"+X",
	"-X",
	"+Y",
	"-Y",
	"+Z",
	"-Z",
]

const EDGE_NAMES := [
	"left",
	"right",
	"top",
	"bottom",
]


static func is_valid_face(face: int) -> bool:
	return face >= 0 and face < FACE_COUNT


static func is_valid_edge(edge: int) -> bool:
	return edge >= 0 and edge < EDGE_COUNT


static func is_valid_uv(uv: Vector2) -> bool:
	return uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0


static func get_face_normal(face: int) -> Vector3:
	assert(is_valid_face(face), "Invalid cube face: %d" % face)
	return FACE_NORMALS[face]


static func get_face_u_axis(face: int) -> Vector3:
	assert(is_valid_face(face), "Invalid cube face: %d" % face)
	return FACE_U_AXES[face]


static func get_face_v_axis(face: int) -> Vector3:
	assert(is_valid_face(face), "Invalid cube face: %d" % face)
	return FACE_V_AXES[face]


static func get_face_name(face: int) -> String:
	return FACE_NAMES[face] if is_valid_face(face) else "invalid(%d)" % face


static func get_edge_name(edge: int) -> String:
	return EDGE_NAMES[edge] if is_valid_edge(edge) else "invalid(%d)" % edge


static func get_face_from_normal(normal: Vector3) -> int:
	for face in range(FACE_COUNT):
		if FACE_NORMALS[face].is_equal_approx(normal):
			return face
	return -1


static func face_uv_to_cube(face: int, uv: Vector2) -> Vector3:
	assert(is_valid_face(face), "Invalid cube face: %d" % face)
	assert(is_valid_uv(uv), "Face UV must be in [0, 1]: %s" % uv)
	var projected := uv * 2.0 - Vector2.ONE
	return get_face_normal(face) \
		+ get_face_u_axis(face) * projected.x \
		+ get_face_v_axis(face) * projected.y


static func face_uv_to_direction(face: int, uv: Vector2) -> Vector3:
	return face_uv_to_cube(face, uv).normalized()


static func direction_to_face_uv(direction: Vector3) -> PlanetFaceUV:
	if direction.is_zero_approx():
		return null

	var normalized := direction.normalized()
	var absolute := normalized.abs()
	var face: int

	# Canonical tie-break: dominant X, then Y, then Z. Strict comparisons
	# preserve the earlier axis when magnitudes are exactly equal.
	if absolute.x >= absolute.y and absolute.x >= absolute.z:
		face = Face.POSITIVE_X if normalized.x >= 0.0 else Face.NEGATIVE_X
	elif absolute.y >= absolute.z:
		face = Face.POSITIVE_Y if normalized.y >= 0.0 else Face.NEGATIVE_Y
	else:
		face = Face.POSITIVE_Z if normalized.z >= 0.0 else Face.NEGATIVE_Z

	var normal := get_face_normal(face)
	var cube_point := normalized / normalized.dot(normal)
	var offset := cube_point - normal
	var projected := Vector2(
		offset.dot(get_face_u_axis(face)),
		offset.dot(get_face_v_axis(face))
	)
	var uv := projected * 0.5 + Vector2(0.5, 0.5)
	uv.x = clampf(uv.x, 0.0, 1.0)
	uv.y = clampf(uv.y, 0.0, 1.0)
	return PlanetFaceUV.new(face, uv)


static func face_uv_to_position(
	face: int,
	uv: Vector2,
	base_radius_units: float,
	radial_height_units: float = 0.0
) -> Vector3:
	assert(base_radius_units > 0.0, "Base radius must be positive.")
	return face_uv_to_direction(face, uv) * (base_radius_units + radial_height_units)
