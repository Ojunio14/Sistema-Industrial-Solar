extends SceneTree

const SAMPLE_COUNT := 4096
const GOLDEN_ANGLE := PI * (3.0 - sqrt(5.0))

var failures: Array[String] = []


func _initialize() -> void:
	var definition: PlanetDefinition = load("res://systems/planet/surface/data/test_planet_100km.tres")
	var shape := PlanetShape.new(definition)
	var duplicate := PlanetShape.new(definition)
	var changed_definition := definition.duplicate() as PlanetDefinition
	changed_definition.seed += 1
	var changed := PlanetShape.new(changed_definition)
	var minimum := INF
	var maximum := -INF
	var maximum_direction := Vector3.ZERO
	var ocean_count := 0
	var changed_count := 0
	var greatest_local_step := 0.0
	var regions: Dictionary = {}

	for index in range(SAMPLE_COUNT):
		var direction := _fibonacci_direction(index, SAMPLE_COUNT)
		var components := shape.sample_components(direction)
		var height := components.x
		minimum = minf(minimum, height)
		if height > maximum:
			maximum = height
			maximum_direction = direction
		ocean_count += 1 if height < definition.sea_level_m else 0
		var region := shape.classify_region(components)
		regions[region] = int(regions.get(region, 0)) + 1
		_expect(is_finite(height), "O relevo produziu valor inválido.")
		_expect(components.y >= 0.0 and components.y <= 1.0, "Máscara de terra fora de 0..1.")
		_expect(components.z >= 0.0 and components.z <= 1.0, "Máscara de montanha fora de 0..1.")
		_expect(components.w >= 0.0 and components.w <= 1.0, "Máscara de planalto fora de 0..1.")
		_expect(is_equal_approx(height, duplicate.sample_height_m(direction)), "A mesma seed mudou o relevo.")
		if absf(height - changed.sample_height_m(direction)) > 0.01:
			changed_count += 1
		var tangent := direction.cross(Vector3.UP)
		if tangent.length_squared() < 0.01:
			tangent = direction.cross(Vector3.RIGHT)
		var neighbor := (direction + tangent.normalized() * 0.0001).normalized()
		greatest_local_step = maxf(greatest_local_step, absf(height - shape.sample_height_m(neighbor)))

	var ocean_fraction := float(ocean_count) / SAMPLE_COUNT
	_expect(minimum >= definition.sea_level_m - definition.ocean_depth_m, "O fundo ultrapassou a profundidade máxima.")
	_expect(maximum <= definition.sea_level_m + definition.natural_max_height_m(), "O pico ultrapassou a altura máxima.")
	_expect(minimum < -80.0, "O planeta precisa de oceano profundo perceptível.")
	_expect(maximum > 250.0, "O planeta precisa de relevo continental perceptível.")
	_expect(ocean_fraction > 0.2 and ocean_fraction < 0.8, "A razão terra/água ficou extrema: %.1f%% de oceano." % (ocean_fraction * 100.0))
	_expect(regions.size() >= 5, "O gerador precisa produzir ao menos cinco regiões distintas.")
	_expect(changed_count > SAMPLE_COUNT / 2, "Trocar a seed deveria alterar a maior parte das amostras.")
	_expect(greatest_local_step < 20.0, "Há descontinuidade local no relevo: %.2f m." % greatest_local_step)

	print("TERRAIN min=%.1f m max=%.1f m ocean=%.1f%% regions=%s local_step=%.3f m peak=%s" % [
		minimum, maximum, ocean_fraction * 100.0, regions, greatest_local_step, maximum_direction])
	if failures.is_empty():
		print("Planet terrain: PASS (%d amostras)." % SAMPLE_COUNT)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _fibonacci_direction(index: int, total: int) -> Vector3:
	var y := 1.0 - 2.0 * (float(index) + 0.5) / float(total)
	var radius := sqrt(maxf(0.0, 1.0 - y * y))
	var angle := GOLDEN_ANGLE * index
	return Vector3(cos(angle) * radius, y, sin(angle) * radius)


func _expect(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
