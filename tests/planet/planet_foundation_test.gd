extends SceneTree

const EPSILON := 0.00001
var _failures: Array[String] = []


func _initialize() -> void:
	_test_planet_scale()
	_test_cube_sphere_round_trip()
	_test_shape_determinism_and_limits()

	if _failures.is_empty():
		print("Planet foundation: todos os testes passaram.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_planet_scale() -> void:
	var definition := PlanetDefinition.new()
	_expect(is_equal_approx(definition.radius_m, 50000.0), "O raio de teste deve ser 50 km.")
	_expect(is_equal_approx(definition.get_diameter_m(), 100000.0), "O diâmetro de teste deve ser 100 km.")


func _test_cube_sphere_round_trip() -> void:
	var samples := [0.0, 0.125, 0.5, 0.875, 1.0]
	for face_index in range(CubeSphereMapping.FACE_NORMALS.size()):
		var face := face_index
		for u in samples:
			for v in samples:
				var direction := CubeSphereMapping.face_uv_to_direction(face, Vector2(u, v))
				var address := CubeSphereMapping.direction_to_face_uv(direction)
				var recovered := CubeSphereMapping.face_uv_to_direction(address.face, address.uv)
				_expect(
					direction.distance_to(recovered) <= EPSILON,
					"Falha no round-trip cubesphere da face %d em (%s, %s)." % [face_index, u, v]
				)


func _test_shape_determinism_and_limits() -> void:
	var definition := PlanetDefinition.new()
	var first_shape := PlanetShape.new(definition)
	var second_shape := PlanetShape.new(definition)
	var directions := [
		Vector3.RIGHT,
		Vector3.UP,
		Vector3.FORWARD,
		Vector3(1.0, 2.0, 3.0).normalized(),
		Vector3(-4.0, 1.0, 2.0).normalized(),
	]

	for direction in directions:
		var first_height := first_shape.sample_height_m(direction)
		var second_height := second_shape.sample_height_m(direction)
		_expect(is_equal_approx(first_height, second_height), "A seed não produziu altura determinística.")
		_expect(
			first_height >= definition.sea_level_m - definition.ocean_depth_m,
			"A altura ficou abaixo da profundidade configurada."
		)
		_expect(
			first_height <= definition.sea_level_m + definition.max_terrain_height_m,
			"A altura ultrapassou o máximo configurado."
		)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
