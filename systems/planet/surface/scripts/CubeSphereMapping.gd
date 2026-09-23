extends RefCounted
class_name CubeSphereMapping

## Conversões canônicas usadas pelo gerador, LOD, colisão e futura edição.

enum Face {
	RIGHT,
	LEFT,
	UP,
	DOWN,
	FRONT,
	BACK,
}

const FACE_NORMALS: Array[Vector3] = [
	Vector3.RIGHT,
	Vector3.LEFT,
	Vector3.UP,
	Vector3.DOWN,
	Vector3(0.0, 0.0, 1.0),
	Vector3(0.0, 0.0, -1.0),
]
const FACE_NAMES := ["Direita", "Esquerda", "Cima", "Baixo", "Frente", "Trás"]


static func face_normal(face: Face) -> Vector3:
	return FACE_NORMALS[int(face)]


static func face_name(face: Face) -> String:
	return FACE_NAMES[int(face)]


static func normal_to_face(normal: Vector3) -> Face:
	var axis := normal.abs()
	if axis.x >= axis.y and axis.x >= axis.z:
		return Face.RIGHT if normal.x >= 0.0 else Face.LEFT
	if axis.y >= axis.z:
		return Face.UP if normal.y >= 0.0 else Face.DOWN
	return Face.FRONT if normal.z >= 0.0 else Face.BACK


static func face_axes(face: Face) -> Array[Vector3]:
	var normal := face_normal(face)
	var axis_a := Vector3(normal.y, normal.z, normal.x)
	var axis_b := normal.cross(axis_a)
	return [axis_a, axis_b]


static func face_uv_to_cube(face: Face, uv: Vector2) -> Vector3:
	var normal := face_normal(face)
	var axes := face_axes(face)
	return normal + (uv.x - 0.5) * 2.0 * axes[0] + (uv.y - 0.5) * 2.0 * axes[1]


static func face_uv_to_direction(face: Face, uv: Vector2) -> Vector3:
	return face_uv_to_cube(face, uv).normalized()


static func direction_to_face_uv(direction: Vector3) -> Dictionary:
	assert(not direction.is_zero_approx(), "A direção do cubesphere não pode ser zero.")
	var normalized := direction.normalized()
	var face := normal_to_face(normalized)
	var normal := face_normal(face)
	var dominant := absf(normalized.dot(normal))
	var cube_point := normalized / dominant
	var offset := cube_point - normal
	var axes := face_axes(face)
	var uv := Vector2(
		offset.dot(axes[0]) * 0.5 + 0.5,
		offset.dot(axes[1]) * 0.5 + 0.5
	)
	return {"face": face, "uv": uv}


static func grid_uv(x: int, y: int, resolution: int) -> Vector2:
	assert(resolution >= 2, "A resolução deve ser pelo menos 2.")
	return Vector2(float(x), float(y)) / float(resolution - 1)
