class_name PlanetTopology
extends RefCounted


static func get_edge_transition(face: int, edge: int) -> PlanetEdgeTransition:
	assert(PlanetMath.is_valid_face(face), "Invalid cube face: %d" % face)
	assert(PlanetMath.is_valid_edge(edge), "Invalid cube edge: %d" % edge)

	var face_normal := PlanetMath.get_face_normal(face)
	var neighbor_normal: Vector3
	var source_tangent: Vector3

	match edge:
		PlanetMath.Edge.LEFT:
			neighbor_normal = -PlanetMath.get_face_u_axis(face)
			source_tangent = PlanetMath.get_face_v_axis(face)
		PlanetMath.Edge.RIGHT:
			neighbor_normal = PlanetMath.get_face_u_axis(face)
			source_tangent = PlanetMath.get_face_v_axis(face)
		PlanetMath.Edge.TOP:
			neighbor_normal = -PlanetMath.get_face_v_axis(face)
			source_tangent = PlanetMath.get_face_u_axis(face)
		PlanetMath.Edge.BOTTOM:
			neighbor_normal = PlanetMath.get_face_v_axis(face)
			source_tangent = PlanetMath.get_face_u_axis(face)

	var neighbor_face := PlanetMath.get_face_from_normal(neighbor_normal)
	assert(neighbor_face >= 0, "Face basis does not resolve to a neighbor.")
	var neighbor_u := PlanetMath.get_face_u_axis(neighbor_face)
	var neighbor_v := PlanetMath.get_face_v_axis(neighbor_face)
	var neighbor_edge := -1
	var neighbor_tangent := Vector3.ZERO

	if face_normal.is_equal_approx(-neighbor_u):
		neighbor_edge = PlanetMath.Edge.LEFT
		neighbor_tangent = neighbor_v
	elif face_normal.is_equal_approx(neighbor_u):
		neighbor_edge = PlanetMath.Edge.RIGHT
		neighbor_tangent = neighbor_v
	elif face_normal.is_equal_approx(-neighbor_v):
		neighbor_edge = PlanetMath.Edge.TOP
		neighbor_tangent = neighbor_u
	elif face_normal.is_equal_approx(neighbor_v):
		neighbor_edge = PlanetMath.Edge.BOTTOM
		neighbor_tangent = neighbor_u

	assert(neighbor_edge >= 0, "Could not resolve the matching edge.")
	return PlanetEdgeTransition.new(
		neighbor_face,
		neighbor_edge,
		source_tangent.dot(neighbor_tangent) < 0.0
	)


static func edge_uv(edge: int, parameter: float) -> Vector2:
	assert(PlanetMath.is_valid_edge(edge), "Invalid cube edge: %d" % edge)
	assert(parameter >= 0.0 and parameter <= 1.0, "Edge parameter must be in [0, 1].")
	match edge:
		PlanetMath.Edge.LEFT:
			return Vector2(0.0, parameter)
		PlanetMath.Edge.RIGHT:
			return Vector2(1.0, parameter)
		PlanetMath.Edge.TOP:
			return Vector2(parameter, 0.0)
		PlanetMath.Edge.BOTTOM:
			return Vector2(parameter, 1.0)
	return Vector2.ZERO


static func get_neighbor_patch(patch: PatchId, edge: int) -> PatchId:
	if patch == null or not patch.is_valid() or not PlanetMath.is_valid_edge(edge):
		return null

	var max_index := patch.get_divisions() - 1
	match edge:
		PlanetMath.Edge.LEFT:
			if patch.x > 0:
				return PatchId.new(patch.face, patch.level, patch.x - 1, patch.y)
		PlanetMath.Edge.RIGHT:
			if patch.x < max_index:
				return PatchId.new(patch.face, patch.level, patch.x + 1, patch.y)
		PlanetMath.Edge.TOP:
			if patch.y > 0:
				return PatchId.new(patch.face, patch.level, patch.x, patch.y - 1)
		PlanetMath.Edge.BOTTOM:
			if patch.y < max_index:
				return PatchId.new(patch.face, patch.level, patch.x, patch.y + 1)

	var transition := get_edge_transition(patch.face, edge)
	var source_parameter := patch.y if edge in [PlanetMath.Edge.LEFT, PlanetMath.Edge.RIGHT] else patch.x
	var mapped_parameter := max_index - source_parameter if transition.is_reversed else source_parameter
	var neighbor_x: int
	var neighbor_y: int

	match transition.neighbor_edge:
		PlanetMath.Edge.LEFT:
			neighbor_x = 0
			neighbor_y = mapped_parameter
		PlanetMath.Edge.RIGHT:
			neighbor_x = max_index
			neighbor_y = mapped_parameter
		PlanetMath.Edge.TOP:
			neighbor_x = mapped_parameter
			neighbor_y = 0
		PlanetMath.Edge.BOTTOM:
			neighbor_x = mapped_parameter
			neighbor_y = max_index

	return PatchId.new(transition.neighbor_face, patch.level, neighbor_x, neighbor_y)
