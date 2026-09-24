class_name PlanetClimate
extends RefCounted
## Clima global estático. PlanetShape é apenas consultado; nunca recebe escrita.
## A consulta quente lê arrays imutáveis e aceita um output pertencente ao caller.
const SEED_SALT := 0x434C4938 # CLI8, namespace diferente da Etapa 5.
const WIDTH := 192
const HEIGHT := 96
const OCEAN_STEPS := 16
const LAPSE_C_PER_M := 0.0065

var _planet_seed: int
var _climate_seed: int
var _sea_level: float
var _phase: float
var _shape: PlanetShape # Somente sample() direto na main thread; workers usam sample_with_surface_into().
var _heights := PackedFloat32Array()
var _land := PackedFloat32Array()
var _mountains := PackedFloat32Array()
var _ocean := PackedFloat32Array()
var _shadow := PackedFloat32Array()
var _windward := PackedFloat32Array()

func _init(definition: PlanetDefinition, climate_seed_override: int = -1) -> void:
	_planet_seed = definition.seed
	_climate_seed = climate_seed_override if climate_seed_override >= 0 else definition.seed ^ SEED_SALT
	_sea_level = definition.sea_level_m
	_phase = float(_hash(_climate_seed) & 65535) * TAU / 65535.0
	_shape = PlanetShape.new(definition.duplicate(true))
	_build_fields()

func get_seed() -> int:
	return _climate_seed

func sample(direction: Vector3) -> PlanetClimateSample:
	var output := PlanetClimateSample.new()
	sample_into(direction, output)
	return output

func sample_position(local_position: Vector3) -> PlanetClimateSample:
	return sample(local_position.normalized())

## Uso direto na main thread. O caminho com surface fornecida é seguro no worker.
func sample_into(direction: Vector3, output: PlanetClimateSample) -> void:
	sample_with_surface_into(direction, _shape.sample_components(direction), output)

## Nenhuma consulta de Resource/Node, RNG, scratch global ou alocação de objeto.
func sample_with_surface_into(direction: Vector3, surface: Vector4,
		output: PlanetClimateSample) -> void:
	var d := direction.normalized()
	var latitude := absf(d.y)
	var altitude := surface.x - _sea_level
	var ocean := maxf(_sample_grid(_ocean, d), (1.0 - surface.y) * 0.85)
	ocean = clampf(ocean, 0.0, 1.0)
	var shadow := clampf(_sample_grid(_shadow, d), 0.0, 1.0)
	var windward := clampf(_sample_grid(_windward, d), 0.0, 1.0)
	var regional := sin(d.x * 5.2 + _phase) * cos(d.z * 4.3 - d.y * 2.7)
	var regional_two := sin(d.z * 3.1 - _phase * 0.7) * cos(d.y * 4.7 + d.x)
	var temperature := temperature_at(latitude, altitude, ocean) + regional * 1.7 + regional_two * 0.7
	var wet_belt := 0.31 + 0.37 * exp(-pow(latitude / 0.27, 2.0)) \
		+ 0.19 * exp(-pow((latitude - 0.66) / 0.17, 2.0)) \
		- 0.23 * exp(-pow((latitude - 0.43) / 0.15, 2.0)) \
		- 0.10 * smoothstep(0.82, 1.0, latitude)
	var humidity := clampf(wet_belt + ocean * 0.28 + regional * 0.065 +
		windward * 0.15 - shadow * 0.40, 0.0, 1.0)
	var precipitation := clampf(humidity * (0.75 + 0.16 * windward) - shadow * 0.12,
		0.0, 1.0)
	output.temperature_c = temperature
	output.humidity = humidity
	output.precipitation = precipitation
	output.ocean_influence = ocean
	output.rain_shadow = shadow
	output.windward = windward
	output.altitude_m = altitude

static func temperature_at(abs_sin_latitude: float, altitude_m: float,
		ocean_influence: float) -> float:
	var base := 30.0 - 55.0 * pow(clampf(abs_sin_latitude, 0.0, 1.0), 1.15)
	var moderated := lerpf(base, 16.0 + (base - 16.0) * 0.75,
		clampf(ocean_influence, 0.0, 1.0) * 0.65)
	return moderated - maxf(0.0, altitude_m) * LAPSE_C_PER_M

## Texturas só são criadas quando F6 é solicitado. Não entram na mesh.
func create_debug_textures() -> Array[Texture2D]:
	var fields := Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGBAF)
	var shadow_image := Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RF)
	var output := PlanetClimateSample.new()
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var i := x + y * WIDTH
			var direction := _grid_direction(x, y)
			sample_with_surface_into(direction,
				Vector4(_heights[i] + _sea_level, _land[i], _mountains[i], 0.0), output)
			fields.set_pixel(x, y, Color(clampf((output.temperature_c + 40.0) / 80.0, 0.0, 1.0),
				output.humidity, output.ocean_influence, output.precipitation))
			shadow_image.set_pixel(x, y, Color(output.rain_shadow, 0.0, 0.0, 1.0))
	return [ImageTexture.create_from_image(fields), ImageTexture.create_from_image(shadow_image)]

static func prevailing_wind(direction: Vector3) -> Vector3:
	var latitude := absf(direction.y)
	var zonal := -1.0 + 2.0 * smoothstep(0.30, 0.52, latitude) \
		- 2.0 * smoothstep(0.74, 0.91, latitude)
	var east := Vector3.UP.cross(direction)
	if east.length_squared() < 0.00000001:
		east = Vector3.RIGHT
	else:
		east = east.normalized()
	var poleward := Vector3.UP - direction * direction.y
	if poleward.length_squared() < 0.00000001:
		poleward = Vector3.FORWARD
	else:
		poleward = poleward.normalized()
	return (east * zonal - poleward * (0.23 * direction.y)).normalized()

func _build_fields() -> void:
	var count := WIDTH * HEIGHT
	_heights.resize(count)
	_land.resize(count)
	_mountains.resize(count)
	_ocean.resize(count)
	_shadow.resize(count)
	_windward.resize(count)
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var i := x + y * WIDTH
			var surface := _shape.sample_components(_grid_direction(x, y))
			var altitude := surface.x - _sea_level
			_heights[i] = altitude
			_land[i] = surface.y
			_mountains[i] = surface.z
			_ocean[i] = 1.0 - smoothstep(-12.0, 25.0, altitude)
	# Distância oceânica aproximada: propagação geodésica local na grade,
	# com custo pago uma vez. Longitude se conecta periodicamente.
	for iteration in range(OCEAN_STEPS):
		var next := _ocean.duplicate()
		for y in range(HEIGHT):
			var latitude := absf(0.5 - (float(y) + 0.5) / HEIGHT) * PI
			var horizontal_decay := exp(-maxf(0.12, cos(latitude)) * TAU / WIDTH / 0.13)
			var vertical_decay := exp(-PI / HEIGHT / 0.13)
			for x in range(WIDTH):
				var i := x + y * WIDTH
				var left := posmod(x - 1, WIDTH) + y * WIDTH
				var right := (x + 1) % WIDTH + y * WIDTH
				var up := x + maxi(y - 1, 0) * WIDTH
				var down := x + mini(y + 1, HEIGHT - 1) * WIDTH
				next[i] = maxf(_ocean[i], maxf(maxf(_ocean[left], _ocean[right]) * horizontal_decay,
					maxf(_ocean[up], _ocean[down]) * vertical_decay))
		_ocean = next
	# Barreiras no relevo real, consultadas via grade ao longo do vento local.
	# Nenhum raymarch ocorre durante sample().
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var i := x + y * WIDTH
			var direction := _grid_direction(x, y)
			var wind := prevailing_wind(direction)
			var altitude := _heights[i]
			var mountain := _mountains[i]
			var lee := 0.0
			var exposed := 0.0
			for step in range(1, 7):
				var upwind := (direction - wind * (float(step) * 0.027)).normalized()
				var upstream_height := _sample_grid(_heights, upwind)
				var upstream_mountain := _sample_grid(_mountains, upwind)
				var reach := 1.0 - float(step - 1) / 7.0
				lee = maxf(lee, clampf((upstream_height - altitude - 45.0) / 350.0, 0.0, 1.0) *
					(0.35 + upstream_mountain * 0.65) * reach)
				exposed = maxf(exposed, clampf((altitude - upstream_height - 30.0) / 300.0, 0.0, 1.0) *
					(0.35 + mountain * 0.65) * reach)
			_shadow[i] = lee
			_windward[i] = exposed
	# Uma passada curta retira marcas quadradas sem apagar a direção da sombra.
	_shadow = _blur(_shadow)
	_windward = _blur(_windward)

static func _blur(field: PackedFloat32Array) -> PackedFloat32Array:
	var result := field.duplicate()
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var i := x + y * WIDTH
			result[i] = 0.5 * field[i] + 0.125 * (
				field[posmod(x - 1, WIDTH) + y * WIDTH] +
				field[(x + 1) % WIDTH + y * WIDTH] +
				field[x + maxi(y - 1, 0) * WIDTH] +
				field[x + mini(y + 1, HEIGHT - 1) * WIDTH])
	return result

static func _grid_direction(x: int, y: int) -> Vector3:
	var longitude := ((float(x) + 0.5) / WIDTH - 0.5) * TAU
	var latitude := (0.5 - (float(y) + 0.5) / HEIGHT) * PI
	var radial := cos(latitude)
	return Vector3(cos(longitude) * radial, sin(latitude), sin(longitude) * radial)

static func _grid_coordinates(direction: Vector3) -> Vector2:
	var longitude := atan2(direction.z, direction.x)
	return Vector2(longitude / TAU + 0.5, 0.5 - asin(clampf(direction.y, -1.0, 1.0)) / PI)

static func _sample_grid(field: PackedFloat32Array, direction: Vector3) -> float:
	var uv := _grid_coordinates(direction)
	var xf := uv.x * WIDTH - 0.5
	var x0 := floori(xf)
	var tx := xf - floorf(xf)
	var y_float := clampf(uv.y * HEIGHT - 0.5, 0.0, float(HEIGHT - 1))
	var y0 := floori(y_float)
	var y1 := mini(y0 + 1, HEIGHT - 1)
	var ty := y_float - float(y0)
	var a := field[posmod(x0, WIDTH) + y0 * WIDTH]
	var b := field[posmod(x0 + 1, WIDTH) + y0 * WIDTH]
	var c := field[posmod(x0, WIDTH) + y1 * WIDTH]
	var d := field[posmod(x0 + 1, WIDTH) + y1 * WIDTH]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)

static func _hash(value: int) -> int:
	var x := value & 0x7fffffff
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0x7fffffff
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0x7fffffff
	return x ^ (x >> 16)
