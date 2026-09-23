class_name PlanetSSE
extends RefCounted

static func center(id: PatchId, radius: float) -> Vector3:
	return PlanetMath.face_uv_to_position(id.face, id.get_uv_bounds().get_center(), radius)

# Normalization is Lipschitz <= 1 on a cube face (length >= 1).
# Cube patch side = 2/divisions, hence center-to-corner = sqrt(2)/divisions.
# This sphere encloses the whole curved patch. Using the full diagonal here
# incorrectly doubled the radius and drove refinement far outside the patch.
static func extent(id: PatchId, radius: float) -> float:
	return radius * sqrt(2.0) / float(id.get_divisions())

static func geometric_error(id: PatchId, radius: float, terrain_error: float = 0.0) -> float:
	var step := 2.0 / (32.0 * float(id.get_divisions()))
	return radius * step * step + maxf(terrain_error, 0.0)

static func pixels(id: PatchId, radius: float, camera: Vector3, viewport_height: float,
		vertical_fov_degrees: float, orthographic_height: float = 0.0, terrain_error: float = 0.0) -> float:
	var error := geometric_error(id, radius, terrain_error)
	return project_error(error, center(id, radius), extent(id, radius), camera, viewport_height, vertical_fov_degrees, orthographic_height)

static func project_error(error: float, patch_center: Vector3, patch_extent: float,
		camera: Vector3, viewport_height: float, vertical_fov_degrees: float, orthographic_height: float = 0.0) -> float:
	if orthographic_height > 0.0:
		return error * viewport_height / orthographic_height
	var distance := maxf(0.1, camera.distance_to(patch_center) - patch_extent)
	return error * viewport_height / (2.0 * tan(deg_to_rad(vertical_fov_degrees) * 0.5) * distance)

static func visible(id: PatchId, radius: float, planes: Array[Plane]) -> bool:
	var point := center(id, radius)
	var bound := extent(id, radius)
	for plane in planes:
		if plane.distance_to(point) > bound:
			return false
	return true
