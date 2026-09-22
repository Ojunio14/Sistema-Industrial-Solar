extends SceneTree

const EPSILON := 0.00001
const EDGE_SAMPLES := [0.0, 0.125, 0.333333, 0.5, 0.777777, 0.9375, 1.0]
const FACE_BASIS_ORACLE := [
	{"face": PlanetMath.Face.POSITIVE_X, "normal": Vector3(1.0, 0.0, 0.0), "u": Vector3(0.0, 0.0, -1.0), "v": Vector3(0.0, 1.0, 0.0)},
	{"face": PlanetMath.Face.NEGATIVE_X, "normal": Vector3(-1.0, 0.0, 0.0), "u": Vector3(0.0, 0.0, 1.0), "v": Vector3(0.0, 1.0, 0.0)},
	{"face": PlanetMath.Face.POSITIVE_Y, "normal": Vector3(0.0, 1.0, 0.0), "u": Vector3(1.0, 0.0, 0.0), "v": Vector3(0.0, 0.0, -1.0)},
	{"face": PlanetMath.Face.NEGATIVE_Y, "normal": Vector3(0.0, -1.0, 0.0), "u": Vector3(1.0, 0.0, 0.0), "v": Vector3(0.0, 0.0, 1.0)},
	{"face": PlanetMath.Face.POSITIVE_Z, "normal": Vector3(0.0, 0.0, 1.0), "u": Vector3(1.0, 0.0, 0.0), "v": Vector3(0.0, 1.0, 0.0)},
	{"face": PlanetMath.Face.NEGATIVE_Z, "normal": Vector3(0.0, 0.0, -1.0), "u": Vector3(-1.0, 0.0, 0.0), "v": Vector3(0.0, 1.0, 0.0)},
]
const TOPOLOGY_ORACLE := [
	{"face": PlanetMath.Face.POSITIVE_X, "edge": PlanetMath.Edge.LEFT, "neighbor_face": PlanetMath.Face.POSITIVE_Z, "neighbor_edge": PlanetMath.Edge.RIGHT, "reversed": false},
	{"face": PlanetMath.Face.POSITIVE_X, "edge": PlanetMath.Edge.RIGHT, "neighbor_face": PlanetMath.Face.NEGATIVE_Z, "neighbor_edge": PlanetMath.Edge.LEFT, "reversed": false},
	{"face": PlanetMath.Face.POSITIVE_X, "edge": PlanetMath.Edge.TOP, "neighbor_face": PlanetMath.Face.NEGATIVE_Y, "neighbor_edge": PlanetMath.Edge.RIGHT, "reversed": true},
	{"face": PlanetMath.Face.POSITIVE_X, "edge": PlanetMath.Edge.BOTTOM, "neighbor_face": PlanetMath.Face.POSITIVE_Y, "neighbor_edge": PlanetMath.Edge.RIGHT, "reversed": false},
	{"face": PlanetMath.Face.NEGATIVE_X, "edge": PlanetMath.Edge.LEFT, "neighbor_face": PlanetMath.Face.NEGATIVE_Z, "neighbor_edge": PlanetMath.Edge.RIGHT, "reversed": false},
	{"face": PlanetMath.Face.NEGATIVE_X, "edge": PlanetMath.Edge.RIGHT, "neighbor_face": PlanetMath.Face.POSITIVE_Z, "neighbor_edge": PlanetMath.Edge.LEFT, "reversed": false},
	{"face": PlanetMath.Face.NEGATIVE_X, "edge": PlanetMath.Edge.TOP, "neighbor_face": PlanetMath.Face.NEGATIVE_Y, "neighbor_edge": PlanetMath.Edge.LEFT, "reversed": false},
	{"face": PlanetMath.Face.NEGATIVE_X, "edge": PlanetMath.Edge.BOTTOM, "neighbor_face": PlanetMath.Face.POSITIVE_Y, "neighbor_edge": PlanetMath.Edge.LEFT, "reversed": true},
	{"face": PlanetMath.Face.POSITIVE_Y, "edge": PlanetMath.Edge.LEFT, "neighbor_face": PlanetMath.Face.NEGATIVE_X, "neighbor_edge": PlanetMath.Edge.BOTTOM, "reversed": true},
	{"face": PlanetMath.Face.POSITIVE_Y, "edge": PlanetMath.Edge.RIGHT, "neighbor_face": PlanetMath.Face.POSITIVE_X, "neighbor_edge": PlanetMath.Edge.BOTTOM, "reversed": false},
	{"face": PlanetMath.Face.POSITIVE_Y, "edge": PlanetMath.Edge.TOP, "neighbor_face": PlanetMath.Face.POSITIVE_Z, "neighbor_edge": PlanetMath.Edge.BOTTOM, "reversed": false},
	{"face": PlanetMath.Face.POSITIVE_Y, "edge": PlanetMath.Edge.BOTTOM, "neighbor_face": PlanetMath.Face.NEGATIVE_Z, "neighbor_edge": PlanetMath.Edge.BOTTOM, "reversed": true},
	{"face": PlanetMath.Face.NEGATIVE_Y, "edge": PlanetMath.Edge.LEFT, "neighbor_face": PlanetMath.Face.NEGATIVE_X, "neighbor_edge": PlanetMath.Edge.TOP, "reversed": false},
	{"face": PlanetMath.Face.NEGATIVE_Y, "edge": PlanetMath.Edge.RIGHT, "neighbor_face": PlanetMath.Face.POSITIVE_X, "neighbor_edge": PlanetMath.Edge.TOP, "reversed": true},
	{"face": PlanetMath.Face.NEGATIVE_Y, "edge": PlanetMath.Edge.TOP, "neighbor_face": PlanetMath.Face.NEGATIVE_Z, "neighbor_edge": PlanetMath.Edge.TOP, "reversed": true},
	{"face": PlanetMath.Face.NEGATIVE_Y, "edge": PlanetMath.Edge.BOTTOM, "neighbor_face": PlanetMath.Face.POSITIVE_Z, "neighbor_edge": PlanetMath.Edge.TOP, "reversed": false},
	{"face": PlanetMath.Face.POSITIVE_Z, "edge": PlanetMath.Edge.LEFT, "neighbor_face": PlanetMath.Face.NEGATIVE_X, "neighbor_edge": PlanetMath.Edge.RIGHT, "reversed": false},
	{"face": PlanetMath.Face.POSITIVE_Z, "edge": PlanetMath.Edge.RIGHT, "neighbor_face": PlanetMath.Face.POSITIVE_X, "neighbor_edge": PlanetMath.Edge.LEFT, "reversed": false},
	{"face": PlanetMath.Face.POSITIVE_Z, "edge": PlanetMath.Edge.TOP, "neighbor_face": PlanetMath.Face.NEGATIVE_Y, "neighbor_edge": PlanetMath.Edge.BOTTOM, "reversed": false},
	{"face": PlanetMath.Face.POSITIVE_Z, "edge": PlanetMath.Edge.BOTTOM, "neighbor_face": PlanetMath.Face.POSITIVE_Y, "neighbor_edge": PlanetMath.Edge.TOP, "reversed": false},
	{"face": PlanetMath.Face.NEGATIVE_Z, "edge": PlanetMath.Edge.LEFT, "neighbor_face": PlanetMath.Face.POSITIVE_X, "neighbor_edge": PlanetMath.Edge.RIGHT, "reversed": false},
	{"face": PlanetMath.Face.NEGATIVE_Z, "edge": PlanetMath.Edge.RIGHT, "neighbor_face": PlanetMath.Face.NEGATIVE_X, "neighbor_edge": PlanetMath.Edge.LEFT, "reversed": false},
	{"face": PlanetMath.Face.NEGATIVE_Z, "edge": PlanetMath.Edge.TOP, "neighbor_face": PlanetMath.Face.NEGATIVE_Y, "neighbor_edge": PlanetMath.Edge.TOP, "reversed": true},
	{"face": PlanetMath.Face.NEGATIVE_Z, "edge": PlanetMath.Edge.BOTTOM, "neighbor_face": PlanetMath.Face.POSITIVE_Y, "neighbor_edge": PlanetMath.Edge.BOTTOM, "reversed": true},
]

var _failure_count := 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_definition_and_planet_lab()
	_test_face_bases()
	_test_topology_oracle()
	_test_face_uv_to_direction()
	_test_edge_continuity()
	_test_inverse_conversion()
	_test_patch_id()
	_test_patch_uv_precision_limit()
	_test_topology_and_patch_neighbors()
	_test_determinism()

	if _failure_count > 0:
		push_error("PLANET_FOUNDATION_TEST_FAILED: %d failure(s)" % _failure_count)
		quit(1)
		return

	print("PLANET_FOUNDATION_TEST_OK: faces/conversions/continuity/PatchId/topology/determinism")
	quit(0)


func _test_definition_and_planet_lab() -> void:
	var definition := load("res://systems/planet/default_planet_definition.tres") as PlanetDefinition
	_check(definition != null, "Default PlanetDefinition must load.")
	if definition == null:
		return
	_check(definition.is_valid(), "Default PlanetDefinition must be valid.")
	_check_close(definition.base_radius_meters, 50000.0, EPSILON, "Base radius must be 50,000 meters.")
	_check_close(definition.meters_per_unit, 1.0, EPSILON, "Scale must be one meter per Godot unit.")
	_check_close(definition.get_base_radius_units(), 50000.0, EPSILON, "Base radius in units is wrong.")

	var surface_position := PlanetMath.face_uv_to_position(
		PlanetMath.Face.POSITIVE_X,
		Vector2(0.37, 0.61),
		definition.get_base_radius_units()
	)
	_check_close(surface_position.length(), 50000.0, 0.01, "Base-surface position has the wrong radius.")
	var raised_position := PlanetMath.face_uv_to_position(
		PlanetMath.Face.POSITIVE_X,
		Vector2(0.37, 0.61),
		definition.get_base_radius_units(),
		123.0
	)
	_check_close(raised_position.length(), 50123.0, 0.01, "Explicit radial height was not applied separately.")

	var packed_lab := load("res://scenes/planet_lab/planet_lab.tscn") as PackedScene
	_check(packed_lab != null, "PlanetLab must load.")
	if packed_lab == null:
		return
	var lab := packed_lab.instantiate()
	var planet := lab.get_node_or_null("Planet") as PlanetRoot
	_check(planet != null, "PlanetLab/Planet must be a PlanetRoot.")
	if planet != null:
		_check(planet.definition != null, "PlanetRoot must expose a PlanetDefinition.")
		_check_close(planet.get_base_radius_units(), 50000.0, EPSILON, "PlanetRoot exposes the wrong radius.")
		_check(planet.get_child_count() == 0, "PlanetRoot must remain empty during Stage 1.")
		_check(not _contains_mesh(planet), "PlanetRoot must not contain planetary mesh geometry.")
	var orbital := lab.get_node_or_null("Cameras/OrbitalCamera")
	_check(orbital != null and orbital.get("target") == planet, "Orbital camera must keep Planet as its target.")
	lab.free()


func _test_face_bases() -> void:
	_check(PlanetMath.FACE_COUNT == 6, "Exactly six cube faces are required.")
	_check(FACE_BASIS_ORACLE.size() == 6, "Face-basis oracle must contain exactly six entries.")
	_check(not PlanetMath.is_valid_face(-1), "Negative face index must be invalid.")
	_check(not PlanetMath.is_valid_face(PlanetMath.FACE_COUNT), "Face index 6 must be invalid.")
	var unique_normals := {}
	var oracle_faces := {}

	for expected in FACE_BASIS_ORACLE:
		var face: int = int(expected["face"])
		_check(PlanetMath.is_valid_face(face), "Face %d must be valid." % face)
		var normal := PlanetMath.get_face_normal(face)
		var axis_u := PlanetMath.get_face_u_axis(face)
		var axis_v := PlanetMath.get_face_v_axis(face)
		var context := "face=%s" % PlanetMath.get_face_name(face)
		_check_vector3(normal, expected["normal"] as Vector3, 0.0, "%s normal differs from the independent oracle." % context)
		_check_vector3(axis_u, expected["u"] as Vector3, 0.0, "%s U differs from the independent oracle." % context)
		_check_vector3(axis_v, expected["v"] as Vector3, 0.0, "%s V differs from the independent oracle." % context)
		_check_close(normal.length(), 1.0, EPSILON, "%s normal is not unit length." % context)
		_check_close(axis_u.length(), 1.0, EPSILON, "%s U axis is not unit length." % context)
		_check_close(axis_v.length(), 1.0, EPSILON, "%s V axis is not unit length." % context)
		_check_close(normal.dot(axis_u), 0.0, EPSILON, "%s normal and U are not orthogonal." % context)
		_check_close(normal.dot(axis_v), 0.0, EPSILON, "%s normal and V are not orthogonal." % context)
		_check_close(axis_u.dot(axis_v), 0.0, EPSILON, "%s U and V are not orthogonal." % context)
		_check_vector3(axis_u.cross(axis_v), normal, EPSILON, "%s basis is not right-handed." % context)
		_check_vector3(PlanetMath.get_face_normal(face), normal, 0.0, "%s basis is not deterministic." % context)
		unique_normals[normal] = true
		oracle_faces[face] = true

	_check(unique_normals.size() == 6, "Face normals must be unique.")
	_check(oracle_faces.size() == 6, "Face-basis oracle must cover six distinct faces.")


func _test_topology_oracle() -> void:
	_check(TOPOLOGY_ORACLE.size() == 24, "Topology oracle must contain 24 directed transitions.")
	var source_pairs := {}
	for expected in TOPOLOGY_ORACLE:
		var face: int = int(expected["face"])
		var edge: int = int(expected["edge"])
		var transition := PlanetTopology.get_edge_transition(face, edge)
		var context := "face=%s edge=%s" % [
			PlanetMath.get_face_name(face),
			PlanetMath.get_edge_name(edge),
		]
		_check(
			transition.neighbor_face == int(expected["neighbor_face"]),
			"Topology neighbor face differs from independent oracle: %s got=%s" % [context, transition]
		)
		_check(
			transition.neighbor_edge == int(expected["neighbor_edge"]),
			"Topology neighbor edge differs from independent oracle: %s got=%s" % [context, transition]
		)
		_check(
			transition.is_reversed == bool(expected["reversed"]),
			"Topology orientation differs from independent oracle: %s got=%s" % [context, transition]
		)
		source_pairs["%d:%d" % [face, edge]] = true
	_check(source_pairs.size() == 24, "Topology oracle must cover every face/edge pair exactly once.")


func _test_face_uv_to_direction() -> void:
	var samples := [
		Vector2(0.5, 0.5),
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(0.0, 1.0),
		Vector2(1.0, 1.0),
		Vector2(0.13, 0.27),
		Vector2(0.81, 0.42),
		Vector2(0.36, 0.94),
	]

	for face in range(PlanetMath.FACE_COUNT):
		var center_direction := PlanetMath.face_uv_to_direction(face, Vector2(0.5, 0.5))
		_check_vector3(
			center_direction,
			PlanetMath.get_face_normal(face),
			EPSILON,
			"Face center does not match its normal: face=%s" % PlanetMath.get_face_name(face)
		)
		for uv in samples:
			var direction := PlanetMath.face_uv_to_direction(face, uv)
			var context := "face=%s uv=%s" % [PlanetMath.get_face_name(face), uv]
			_check_close(direction.length(), 1.0, EPSILON, "Direction is not unit length: %s" % context)
			_check_vector3(
				direction,
				PlanetMath.face_uv_to_direction(face, uv),
				0.0,
				"Face UV conversion is not deterministic: %s" % context
			)


func _test_edge_continuity() -> void:
	var visited_physical_edges := {}
	var physical_edge_count := 0

	for face in range(PlanetMath.FACE_COUNT):
		for edge in range(PlanetMath.EDGE_COUNT):
			var transition := PlanetTopology.get_edge_transition(face, edge)
			var source_id := "%d:%d" % [face, edge]
			var neighbor_id := "%d:%d" % [transition.neighbor_face, transition.neighbor_edge]
			var pair_key := source_id + "|" + neighbor_id
			if source_id.naturalnocasecmp_to(neighbor_id) > 0:
				pair_key = neighbor_id + "|" + source_id
			if visited_physical_edges.has(pair_key):
				continue
			visited_physical_edges[pair_key] = true
			physical_edge_count += 1

			var reverse := PlanetTopology.get_edge_transition(
				transition.neighbor_face,
				transition.neighbor_edge
			)
			var context := "face=%s edge=%s" % [
				PlanetMath.get_face_name(face),
				PlanetMath.get_edge_name(edge),
			]
			_check(reverse.neighbor_face == face, "Topology is not reciprocal: %s" % context)
			_check(reverse.neighbor_edge == edge, "Reciprocal edge is wrong: %s" % context)
			_check(reverse.is_reversed == transition.is_reversed, "Reversal is not reciprocal: %s" % context)

			for parameter in EDGE_SAMPLES:
				var neighbor_parameter: float = 1.0 - parameter if transition.is_reversed else parameter
				var direction_a := PlanetMath.face_uv_to_direction(
					face,
					PlanetTopology.edge_uv(edge, parameter)
				)
				var direction_b := PlanetMath.face_uv_to_direction(
					transition.neighbor_face,
					PlanetTopology.edge_uv(transition.neighbor_edge, neighbor_parameter)
				)
				_check_vector3(
					direction_a,
					direction_b,
					EPSILON,
					"Discontinuous physical edge: %s parameter=%f neighbor=%s/%s reversed=%s" % [
						context,
						parameter,
						PlanetMath.get_face_name(transition.neighbor_face),
						PlanetMath.get_edge_name(transition.neighbor_edge),
						transition.is_reversed,
					]
				)

	_check(physical_edge_count == 12, "Cube must expose exactly 12 physical edges; got %d." % physical_edge_count)


func _test_inverse_conversion() -> void:
	var samples := [
		Vector2(0.5, 0.5),
		Vector2(0.23, 0.41),
		Vector2(0.79, 0.68),
		Vector2(0.000001, 0.37),
		Vector2(0.999999, 0.62),
		Vector2(0.42, 0.000001),
		Vector2(0.58, 0.999999),
		Vector2(0.0, 0.5),
		Vector2(1.0, 0.5),
		Vector2(0.5, 0.0),
		Vector2(0.5, 1.0),
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(0.0, 1.0),
		Vector2(1.0, 1.0),
	]

	_check(PlanetMath.direction_to_face_uv(Vector3.ZERO) == null, "Zero direction must not produce Face UV.")
	for face in range(PlanetMath.FACE_COUNT):
		for uv in samples:
			var direction := PlanetMath.face_uv_to_direction(face, uv)
			var canonical := PlanetMath.direction_to_face_uv(direction)
			var context := "face=%s uv=%s" % [PlanetMath.get_face_name(face), uv]
			_check(canonical != null, "Inverse conversion returned null: %s" % context)
			if canonical == null:
				continue
			var reconstructed := PlanetMath.face_uv_to_direction(canonical.face, canonical.uv)
			_check_vector3(direction, reconstructed, EPSILON, "Inverse round-trip changed direction: %s" % context)
			if uv.x > 0.0 and uv.x < 1.0 and uv.y > 0.0 and uv.y < 1.0:
				_check(canonical.face == face, "Interior point changed canonical face: %s" % context)
				_check_vector2(canonical.uv, uv, EPSILON, "Interior point changed UV: %s" % context)

	var edge_tie_cases := [
		{"direction": Vector3(1.0, 1.0, 0.0), "face": PlanetMath.Face.POSITIVE_X},
		{"direction": Vector3(-1.0, 1.0, 0.0), "face": PlanetMath.Face.NEGATIVE_X},
		{"direction": Vector3(0.0, 1.0, 1.0), "face": PlanetMath.Face.POSITIVE_Y},
		{"direction": Vector3(0.0, -1.0, -1.0), "face": PlanetMath.Face.NEGATIVE_Y},
	]
	for tie_case in edge_tie_cases:
		var result := PlanetMath.direction_to_face_uv(tie_case["direction"] as Vector3)
		_check(
			result != null and result.face == tie_case["face"],
			"Canonical X>Y>Z tie-break failed for direction=%s; got=%s" % [
				tie_case["direction"],
				result,
			]
		)

	var corner_tie_cases := [
		{"direction": Vector3(1.0, 1.0, 1.0), "face": PlanetMath.Face.POSITIVE_X},
		{"direction": Vector3(1.0, 1.0, -1.0), "face": PlanetMath.Face.POSITIVE_X},
		{"direction": Vector3(1.0, -1.0, 1.0), "face": PlanetMath.Face.POSITIVE_X},
		{"direction": Vector3(1.0, -1.0, -1.0), "face": PlanetMath.Face.POSITIVE_X},
		{"direction": Vector3(-1.0, 1.0, 1.0), "face": PlanetMath.Face.NEGATIVE_X},
		{"direction": Vector3(-1.0, 1.0, -1.0), "face": PlanetMath.Face.NEGATIVE_X},
		{"direction": Vector3(-1.0, -1.0, 1.0), "face": PlanetMath.Face.NEGATIVE_X},
		{"direction": Vector3(-1.0, -1.0, -1.0), "face": PlanetMath.Face.NEGATIVE_X},
	]
	for corner_case in corner_tie_cases:
		var result := PlanetMath.direction_to_face_uv(corner_case["direction"] as Vector3)
		_check(
			result != null and result.face == corner_case["face"],
			"Canonical X>Y>Z corner tie-break failed for direction=%s; got=%s" % [
				corner_case["direction"],
				result,
			]
		)


func _test_patch_id() -> void:
	var root_keys := {}
	for face in range(PlanetMath.FACE_COUNT):
		var root_patch := PatchId.root(face)
		_check(root_patch.is_valid(), "Root patch is invalid: %s" % root_patch)
		_check(root_patch.level == 0 and root_patch.x == 0 and root_patch.y == 0, "Root coordinates are wrong: %s" % root_patch)
		_check(root_patch.get_parent_id() == null, "Root must not have a parent: %s" % root_patch)
		_check(root_patch.get_quadrant() == -1, "Root must not have a quadrant: %s" % root_patch)
		_check(root_patch.get_uv_bounds() == Rect2(Vector2.ZERO, Vector2.ONE), "Root bounds must cover the full face: %s" % root_patch)
		root_keys[root_patch.stable_key()] = true
		_validate_children_cover_parent(root_patch)
	_check(root_keys.size() == 6, "Root stable keys must be unique across faces.")

	var patch := PatchId.new(PlanetMath.Face.POSITIVE_Z, 3, 2, 5)
	_check(patch.is_valid(), "Representative patch must be valid: %s" % patch)
	_check(patch.get_parent_id().is_equal(PatchId.new(PlanetMath.Face.POSITIVE_Z, 2, 1, 2)), "Patch parent is wrong: %s" % patch)
	_check(patch.get_quadrant() == PatchId.Quadrant.BOTTOM_LEFT, "Patch quadrant is wrong: %s" % patch)
	var bounds := patch.get_uv_bounds()
	_check_vector2(bounds.position, Vector2(0.25, 0.625), EPSILON, "Patch bounds origin is wrong: %s" % patch)
	_check_vector2(bounds.size, Vector2(0.125, 0.125), EPSILON, "Patch bounds size is wrong: %s" % patch)
	_check_vector2(patch.local_uv_to_face_uv(Vector2.ZERO), bounds.position, EPSILON, "Local UV origin mapping failed: %s" % patch)
	_check_vector2(patch.local_uv_to_face_uv(Vector2.ONE), bounds.end, EPSILON, "Local UV end mapping failed: %s" % patch)
	_check_vector2(patch.local_uv_to_face_uv(Vector2(0.5, 0.5)), bounds.get_center(), EPSILON, "Local UV center mapping failed: %s" % patch)
	_validate_children_cover_parent(patch)

	var same_value := PatchId.new(patch.face, patch.level, patch.x, patch.y)
	_check(patch != same_value, "PatchId instances should be distinct objects in this test.")
	_check(patch.is_equal(same_value), "PatchId logical equality must compare values.")
	_check(patch.stable_key() == same_value.stable_key(), "Equivalent PatchIds must have the same stable key.")
	_check(not patch.is_equal(PatchId.new(patch.face, patch.level, patch.x + 1, patch.y)), "Different PatchIds must not compare equal.")

	var level := 5
	var divisions := 1 << level
	_check(PatchId.new(0, level, divisions - 1, divisions - 1).is_valid(), "Maximum x/y at a level must be valid.")
	_check(not PatchId.new(0, level, divisions, divisions - 1).is_valid(), "x == 2^L must be invalid.")
	_check(not PatchId.new(0, level, divisions - 1, divisions).is_valid(), "y == 2^L must be invalid.")
	_check(not PatchId.new(-1, 0, 0, 0).is_valid(), "Invalid face must invalidate PatchId.")
	_check(not PatchId.new(0, -1, 0, 0).is_valid(), "Negative level must invalidate PatchId.")
	_check(not PatchId.new(0, 1, -1, 0).is_valid(), "Negative x must invalidate PatchId.")
	_check(not PatchId.new(0, 1, 0, -1).is_valid(), "Negative y must invalidate PatchId.")
	_check(PatchId.MAX_LEVEL == 24, "PatchId.MAX_LEVEL must protect float32 UV uniqueness at level 24.")
	_check(not PatchId.new(0, PatchId.MAX_LEVEL + 1, 0, 0).is_valid(), "Level above MAX_LEVEL must be invalid.")
	_check(PatchId.new(0, PatchId.MAX_LEVEL, 0, 0).get_children_ids().is_empty(), "MAX_LEVEL patch must not create children.")


func _test_patch_uv_precision_limit() -> void:
	var level := PatchId.MAX_LEVEL
	var divisions := 1 << level
	var max_index := divisions - 1
	var invalid_level_25 := PatchId.new(PlanetMath.Face.POSITIVE_X, 25, 0, 0)
	_check(not invalid_level_25.is_valid(), "PatchId level 25 must be rejected.")
	_check(invalid_level_25.get_divisions() == 0, "Invalid level 25 must not expose subdivisions.")
	_check(invalid_level_25.get_uv_bounds() == Rect2(), "Invalid level 25 must not expose UV bounds.")

	var before_u := PatchId.new(PlanetMath.Face.POSITIVE_X, level, max_index - 1, max_index)
	var last_u := PatchId.new(PlanetMath.Face.POSITIVE_X, level, max_index, max_index)
	var before_v := PatchId.new(PlanetMath.Face.POSITIVE_X, level, max_index, max_index - 1)
	var last_v := PatchId.new(PlanetMath.Face.POSITIVE_X, level, max_index, max_index)
	var samples := [before_u, last_u, before_v, last_v]
	for sample in samples:
		var patch: PatchId = sample
		_check(patch.is_valid(), "Level-24 precision sample must be valid: %s" % patch)
		var bounds: Rect2 = patch.get_uv_bounds()
		_check(bounds.size.x > 0.0 and bounds.size.y > 0.0, "Level-24 UV size must remain positive: %s bounds=%s" % [patch, bounds])
		_check_vector2(patch.local_uv_to_face_uv(Vector2.ZERO), bounds.position, 0.0, "Local UV origin is incoherent at level 24: %s" % patch)
		_check_vector2(patch.local_uv_to_face_uv(Vector2.ONE), bounds.end, 0.0, "Local UV end is incoherent at level 24: %s" % patch)
		var mapped_center: Vector2 = patch.local_uv_to_face_uv(Vector2(0.5, 0.5))
		_check(
			mapped_center.x >= bounds.position.x and mapped_center.x <= bounds.end.x \
				and mapped_center.y >= bounds.position.y and mapped_center.y <= bounds.end.y,
			"Local UV center escaped level-24 bounds: %s mapped=%s bounds=%s" % [patch, mapped_center, bounds]
		)

	var before_u_bounds := before_u.get_uv_bounds()
	var last_u_bounds := last_u.get_uv_bounds()
	var before_v_bounds := before_v.get_uv_bounds()
	var last_v_bounds := last_v.get_uv_bounds()
	_check(before_u_bounds != last_u_bounds, "Adjacent level-24 bounds near u=1 must remain distinct.")
	_check(before_v_bounds != last_v_bounds, "Adjacent level-24 bounds near v=1 must remain distinct.")
	_check(before_u_bounds.position.x < last_u_bounds.position.x, "Adjacent level-24 U origins must be ordered.")
	_check(before_v_bounds.position.y < last_v_bounds.position.y, "Adjacent level-24 V origins must be ordered.")
	_check_close(before_u_bounds.end.x, last_u_bounds.position.x, 0.0, "Adjacent level-24 U bounds must share one edge.")
	_check_close(before_v_bounds.end.y, last_v_bounds.position.y, 0.0, "Adjacent level-24 V bounds must share one edge.")
	_check_close(last_u_bounds.end.x, 1.0, 0.0, "Extreme level-24 patch must end at u=1.")
	_check_close(last_v_bounds.end.y, 1.0, 0.0, "Extreme level-24 patch must end at v=1.")
	_check_vector2(last_u.local_uv_to_face_uv(Vector2.ONE), Vector2.ONE, 0.0, "Extreme level-24 local UV must end at (1,1).")
	_check_vector2(
		before_u.local_uv_to_face_uv(Vector2(1.0, 0.0)),
		last_u.local_uv_to_face_uv(Vector2(0.0, 0.0)),
		0.0,
		"Adjacent level-24 patches must agree on their shared U edge."
	)
	_check_vector2(
		before_v.local_uv_to_face_uv(Vector2(0.0, 1.0)),
		last_v.local_uv_to_face_uv(Vector2(0.0, 0.0)),
		0.0,
		"Adjacent level-24 patches must agree on their shared V edge."
	)


func _test_topology_and_patch_neighbors() -> void:
	var internal := PatchId.new(PlanetMath.Face.POSITIVE_Z, 3, 3, 4)
	var internal_expected := {
		PlanetMath.Edge.LEFT: PatchId.new(internal.face, internal.level, 2, 4),
		PlanetMath.Edge.RIGHT: PatchId.new(internal.face, internal.level, 4, 4),
		PlanetMath.Edge.TOP: PatchId.new(internal.face, internal.level, 3, 3),
		PlanetMath.Edge.BOTTOM: PatchId.new(internal.face, internal.level, 3, 5),
	}
	for edge in range(PlanetMath.EDGE_COUNT):
		var neighbor := PlanetTopology.get_neighbor_patch(internal, edge)
		_check(neighbor.is_equal(internal_expected[edge]), "Internal neighbor is wrong: patch=%s edge=%s got=%s" % [
			internal,
			PlanetMath.get_edge_name(edge),
			neighbor,
		])

	for level_value in [0, 1, 2, 4, 5, 17, 24]:
		var level: int = int(level_value)
		var divisions: int = 1 << level
		var representative_indices := _representative_indices(divisions - 1)
		for face in range(PlanetMath.FACE_COUNT):
			for edge in range(PlanetMath.EDGE_COUNT):
				var transition := PlanetTopology.get_edge_transition(face, edge)
				for source_parameter in representative_indices:
					var patch := _make_boundary_patch(face, level, edge, source_parameter)
					var neighbor := PlanetTopology.get_neighbor_patch(patch, edge)
					var context := "patch=%s edge=%s transition=%s" % [
						patch,
						PlanetMath.get_edge_name(edge),
						transition,
					]
					_check(neighbor != null and neighbor.is_valid(), "Cross-face neighbor is invalid: %s" % context)
					if neighbor == null or not neighbor.is_valid():
						continue
					_check(neighbor.face == transition.neighbor_face, "Cross-face neighbor uses wrong face: %s got=%s" % [context, neighbor])
					_check(neighbor.level == level, "Neighbor level changed: %s got=%s" % [context, neighbor])
					var expected_parameter: int = divisions - 1 - source_parameter if transition.is_reversed else source_parameter
					_check(_edge_parameter(neighbor, transition.neighbor_edge) == expected_parameter, "Neighbor edge parameter is wrong: %s got=%s" % [context, neighbor])
					var round_trip := PlanetTopology.get_neighbor_patch(neighbor, transition.neighbor_edge)
					_check(round_trip != null and round_trip.is_equal(patch), "Neighbor round-trip failed: %s neighbor=%s returned=%s" % [
						context,
						neighbor,
						round_trip,
					])
			_test_representative_same_face_neighbors(face, level, divisions)

	_check(PlanetTopology.get_neighbor_patch(null, PlanetMath.Edge.LEFT) == null, "Null patch must not produce a neighbor.")
	_check(PlanetTopology.get_neighbor_patch(PatchId.new(), PlanetMath.Edge.LEFT) == null, "Invalid patch must not produce a neighbor.")


func _test_determinism() -> void:
	var patch := PatchId.new(PlanetMath.Face.NEGATIVE_Y, 6, 17, 42)
	var direction := Vector3(3.0, -5.0, 7.0)
	var expected_face_uv := PlanetMath.direction_to_face_uv(direction)
	var expected_neighbor := PlanetTopology.get_neighbor_patch(patch, PlanetMath.Edge.RIGHT)
	var expected_transition := PlanetTopology.get_edge_transition(patch.face, PlanetMath.Edge.BOTTOM)

	for iteration in range(100):
		var face_uv := PlanetMath.direction_to_face_uv(direction)
		var neighbor := PlanetTopology.get_neighbor_patch(patch, PlanetMath.Edge.RIGHT)
		var transition := PlanetTopology.get_edge_transition(patch.face, PlanetMath.Edge.BOTTOM)
		_check(face_uv.is_equal(expected_face_uv, 0.0), "Direction conversion changed at iteration %d." % iteration)
		_check(neighbor.is_equal(expected_neighbor), "Patch neighbor changed at iteration %d." % iteration)
		_check(
			transition.neighbor_face == expected_transition.neighbor_face \
				and transition.neighbor_edge == expected_transition.neighbor_edge \
				and transition.is_reversed == expected_transition.is_reversed,
			"Edge transition changed at iteration %d." % iteration
		)


func _validate_children_cover_parent(parent: PatchId) -> void:
	var children := parent.get_children_ids()
	_check(children.size() == 4, "Patch must have four children: %s" % parent)
	if children.size() != 4:
		return
	var expected_quadrants := [
		PatchId.Quadrant.TOP_LEFT,
		PatchId.Quadrant.TOP_RIGHT,
		PatchId.Quadrant.BOTTOM_LEFT,
		PatchId.Quadrant.BOTTOM_RIGHT,
	]
	var total_area := 0.0
	var keys := {}
	for index in range(children.size()):
		var child: PatchId = children[index]
		_check(child.is_valid(), "Child is invalid: parent=%s child=%s" % [parent, child])
		_check(child.get_parent_id().is_equal(parent), "Child parent round-trip failed: parent=%s child=%s" % [parent, child])
		_check(child.get_quadrant() == expected_quadrants[index], "Child quadrant/order is wrong: parent=%s child=%s" % [parent, child])
		var child_bounds := child.get_uv_bounds()
		total_area += child_bounds.get_area()
		keys[child.stable_key()] = true
		_check(parent.get_uv_bounds().encloses(child_bounds), "Child bounds escape parent: parent=%s child=%s" % [parent, child])
	for first in range(children.size()):
		for second in range(first + 1, children.size()):
			_check(
				not children[first].get_uv_bounds().intersection(children[second].get_uv_bounds()).has_area(),
				"Children overlap by area: parent=%s first=%s second=%s" % [parent, children[first], children[second]]
			)
	_check(keys.size() == 4, "Child stable keys are not unique: %s" % parent)
	_check_close(total_area, parent.get_uv_bounds().get_area(), EPSILON, "Children do not cover parent area: %s" % parent)


func _representative_indices(max_index: int) -> Array[int]:
	var result: Array[int] = []
	var candidates: Array[int] = [0, max_index, 1, max_index - 1, max_index >> 1]
	for candidate in candidates:
		if candidate >= 0 and candidate <= max_index and not result.has(candidate):
			result.append(candidate)
	return result


func _test_representative_same_face_neighbors(face: int, level: int, divisions: int) -> void:
	if divisions < 4:
		return
	var max_index := divisions - 1
	var middle := divisions >> 1
	var near_edge_cases := [
		{"patch": PatchId.new(face, level, 1, middle), "edge": PlanetMath.Edge.LEFT, "expected": PatchId.new(face, level, 0, middle)},
		{"patch": PatchId.new(face, level, max_index - 1, middle), "edge": PlanetMath.Edge.RIGHT, "expected": PatchId.new(face, level, max_index, middle)},
		{"patch": PatchId.new(face, level, middle, 1), "edge": PlanetMath.Edge.TOP, "expected": PatchId.new(face, level, middle, 0)},
		{"patch": PatchId.new(face, level, middle, max_index - 1), "edge": PlanetMath.Edge.BOTTOM, "expected": PatchId.new(face, level, middle, max_index)},
	]
	for test_case in near_edge_cases:
		var patch: PatchId = test_case["patch"]
		var edge: int = int(test_case["edge"])
		var expected: PatchId = test_case["expected"]
		var neighbor := PlanetTopology.get_neighbor_patch(patch, edge)
		_check(neighbor != null and neighbor.is_equal(expected), "Near-edge same-face neighbor is wrong: patch=%s edge=%s got=%s expected=%s" % [
			patch,
			PlanetMath.get_edge_name(edge),
			neighbor,
			expected,
		])
		if neighbor != null:
			var round_trip := PlanetTopology.get_neighbor_patch(neighbor, _opposite_edge(edge))
			_check(round_trip != null and round_trip.is_equal(patch), "Near-edge same-face reciprocity failed: patch=%s edge=%s neighbor=%s" % [
				patch,
				PlanetMath.get_edge_name(edge),
				neighbor,
			])

	var internal := PatchId.new(face, level, middle, middle)
	for edge in range(PlanetMath.EDGE_COUNT):
		var neighbor := PlanetTopology.get_neighbor_patch(internal, edge)
		_check(neighbor != null and neighbor.is_valid() and neighbor.face == face, "Representative internal neighbor is invalid: patch=%s edge=%s got=%s" % [
			internal,
			PlanetMath.get_edge_name(edge),
			neighbor,
		])
		if neighbor != null:
			var round_trip := PlanetTopology.get_neighbor_patch(neighbor, _opposite_edge(edge))
			_check(round_trip != null and round_trip.is_equal(internal), "Representative internal reciprocity failed: patch=%s edge=%s neighbor=%s" % [
				internal,
				PlanetMath.get_edge_name(edge),
				neighbor,
			])


func _opposite_edge(edge: int) -> int:
	match edge:
		PlanetMath.Edge.LEFT:
			return PlanetMath.Edge.RIGHT
		PlanetMath.Edge.RIGHT:
			return PlanetMath.Edge.LEFT
		PlanetMath.Edge.TOP:
			return PlanetMath.Edge.BOTTOM
		PlanetMath.Edge.BOTTOM:
			return PlanetMath.Edge.TOP
	return -1


func _make_boundary_patch(face: int, level: int, edge: int, parameter: int) -> PatchId:
	var max_index := (1 << level) - 1
	match edge:
		PlanetMath.Edge.LEFT:
			return PatchId.new(face, level, 0, parameter)
		PlanetMath.Edge.RIGHT:
			return PatchId.new(face, level, max_index, parameter)
		PlanetMath.Edge.TOP:
			return PatchId.new(face, level, parameter, 0)
		PlanetMath.Edge.BOTTOM:
			return PatchId.new(face, level, parameter, max_index)
	return PatchId.new()


func _edge_parameter(patch: PatchId, edge: int) -> int:
	return patch.y if edge in [PlanetMath.Edge.LEFT, PlanetMath.Edge.RIGHT] else patch.x


func _contains_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		return true
	for child in node.get_children():
		if _contains_mesh(child):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error("PLANET_FOUNDATION_ASSERTION: " + message)


func _check_close(actual: float, expected: float, epsilon: float, message: String) -> void:
	_check(absf(actual - expected) <= epsilon, "%s actual=%f expected=%f epsilon=%f" % [
		message,
		actual,
		expected,
		epsilon,
	])


func _check_vector2(actual: Vector2, expected: Vector2, epsilon: float, message: String) -> void:
	_check(actual.distance_to(expected) <= epsilon, "%s actual=%s expected=%s epsilon=%f" % [
		message,
		actual,
		expected,
		epsilon,
	])


func _check_vector3(actual: Vector3, expected: Vector3, epsilon: float, message: String) -> void:
	_check(actual.distance_to(expected) <= epsilon, "%s actual=%s expected=%s epsilon=%f" % [
		message,
		actual,
		expected,
		epsilon,
	])
