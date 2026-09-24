extends RefCounted
## Frozen Stage 9 oracle fixture. Test-only; never used by runtime.

## Fonte determinística do relevo. Todas as entradas usam direção 3D, portanto
## o ruído atravessa as seis faces sem depender de UV ou do nível de detalhe.

enum TerrainRegion {
	DEEP_OCEAN,
	SHALLOW_OCEAN,
	COAST,
	LOWLAND,
	PLATEAU,
	MOUNTAIN,
	ALPINE,
}

const REGION_NAMES := [
	"Oceano profundo", "Oceano raso", "Costa", "Planície",
	"Planalto", "Montanha", "Alpino",
]

var definition: PlanetDefinition
var _continent_noise := FastNoiseLite.new()
var _warp_noise := FastNoiseLite.new()
var _hill_noise := FastNoiseLite.new()
var _plateau_noise := FastNoiseLite.new()
var _mountain_noise := FastNoiseLite.new()
var _belt_noise := FastNoiseLite.new()
var _valley_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()


func _init(planet_definition: PlanetDefinition) -> void:
	definition = planet_definition
	_configure_noises()


func _configure_noises() -> void:
	_configure(_continent_noise, definition.seed, FastNoiseLite.FRACTAL_FBM, 5, 0.5)
	_configure(_warp_noise, definition.seed + 157, FastNoiseLite.FRACTAL_FBM, 3, 0.5)
	_configure(_hill_noise, definition.seed + 409, FastNoiseLite.FRACTAL_FBM, 4, 0.48)
	_configure(_plateau_noise, definition.seed + 673, FastNoiseLite.FRACTAL_FBM, 3, 0.52)
	_configure(_mountain_noise, definition.seed + 1013, FastNoiseLite.FRACTAL_RIDGED, 5, 0.48)
	_configure(_belt_noise, definition.seed + 1459, FastNoiseLite.FRACTAL_FBM, 3, 0.5)
	_configure(_valley_noise, definition.seed + 2027, FastNoiseLite.FRACTAL_FBM, 4, 0.5)
	_configure(_detail_noise, definition.seed + 2521, FastNoiseLite.FRACTAL_FBM, 3, 0.45)


static func _configure(noise: FastNoiseLite, seed: int, fractal: FastNoiseLite.FractalType,
		octaves: int, gain: float) -> void:
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0
	noise.fractal_type = fractal
	noise.fractal_octaves = octaves
	noise.fractal_gain = gain


## x = altura (m), y = máscara de terra, z = montanha, w = planalto.
func sample_components(direction: Vector3) -> Vector4:
	assert(not direction.is_zero_approx(), "Não é possível amostrar o centro do planeta.")
	var p := direction.normalized()
	var warp_scale := definition.continent_warp_scale
	var warp := Vector3(
		_warp_noise.get_noise_3dv(p * warp_scale + Vector3(19.1, 3.7, 11.8)),
		_warp_noise.get_noise_3dv(p * warp_scale + Vector3(-5.2, 17.4, 2.3)),
		_warp_noise.get_noise_3dv(p * warp_scale + Vector3(7.6, -9.8, 23.5))
	)
	var warped := (p + warp * definition.continent_warp_strength).normalized()
	var continental := _continent_noise.get_noise_3dv(warped * definition.continent_scale)
	var threshold := definition.continent_threshold
	var coast := definition.coast_blend
	var land := smoothstep(threshold - coast, threshold + coast, continental)
	var interior := smoothstep(0.3, 0.92, land)
	var continent_height := clampf((continental - threshold) / maxf(1.0 - threshold, 0.01), 0.0, 1.0)

	# O fundo se eleva antes da costa e produz uma plataforma continental suave.
	var shelf := smoothstep(threshold - coast * 2.5, threshold - coast * 0.1, continental)
	var ocean_floor := lerpf(-definition.ocean_depth_m, -definition.ocean_depth_m * 0.16, shelf)

	var hill_raw := _hill_noise.get_noise_3dv(warped * definition.hill_scale) * 0.5 + 0.5
	var hills := (hill_raw - 0.5) * 2.0 * definition.hill_height_m
	var lowlands := 18.0 + pow(continent_height, 0.72) * definition.lowland_height_m + hills

	var plateau_raw := _plateau_noise.get_noise_3dv(warped * definition.plateau_scale) * 0.5 + 0.5
	var plateau_mask := smoothstep(0.56, 0.78, plateau_raw) * interior
	var plateau_height := definition.plateau_height_m * plateau_mask
	var unstepped := lowlands + plateau_height
	var stepped: float = roundf(unstepped / definition.terrace_step_m) * definition.terrace_step_m
	unstepped = lerpf(unstepped, stepped, definition.terrace_strength * plateau_mask)

	# Faixas tectônicas largas modulam cristas menores para evitar montanhas em toda parte.
	var belt_raw := 1.0 - absf(_belt_noise.get_noise_3dv(warped * definition.mountain_belt_scale))
	var belt := smoothstep(0.68, 0.94, belt_raw) * interior
	var ridge_raw := _mountain_noise.get_noise_3dv(warped * definition.mountain_scale) * 0.5 + 0.5
	var ridge := pow(smoothstep(0.5, 0.88, ridge_raw), definition.mountain_ridge_power)
	var mountain_mask := ridge * belt
	var mountains := mountain_mask * definition.mountain_height_m

	# Linhas estreitas retiram altura de planícies e encostas, sugerindo drenagem.
	var valley_raw := 1.0 - absf(_valley_noise.get_noise_3dv(warped * definition.valley_scale))
	var valley_mask := smoothstep(0.86, 0.985, valley_raw) * interior
	var valleys := valley_mask * definition.valley_depth_m * (0.35 + mountain_mask * 0.65)

	var detail := _detail_noise.get_noise_3dv(p * definition.detail_scale)
	detail *= definition.detail_height_m * land
	var land_height := unstepped + mountains - valleys + detail
	var height := lerpf(ocean_floor, maxf(land_height, -8.0), land)
	height += definition.sea_level_m
	height = clampf(height, definition.sea_level_m - definition.ocean_depth_m,
		definition.sea_level_m + definition.max_terrain_height_m)
	return Vector4(height, land, mountain_mask, plateau_mask)


func sample_height_m(direction: Vector3) -> float:
	return sample_components(direction).x


func sample_radius_m(direction: Vector3) -> float:
	return definition.radius_m + sample_height_m(direction)


func point_on_planet(direction: Vector3) -> Vector3:
	return direction.normalized() * sample_radius_m(direction)


func sample_normalized_height(direction: Vector3) -> float:
	return normalize_height(sample_height_m(direction))


func normalize_height(height_m: float) -> float:
	var height_range := definition.max_terrain_height_m + definition.ocean_depth_m
	if is_zero_approx(height_range):
		return 0.0
	return clampf((height_m - definition.sea_level_m + definition.ocean_depth_m) / height_range, 0.0, 1.0)


func classify_region(components: Vector4) -> TerrainRegion:
	var relative_height := components.x - definition.sea_level_m
	if relative_height < -definition.ocean_depth_m * 0.42:
		return TerrainRegion.DEEP_OCEAN
	if relative_height < -8.0:
		return TerrainRegion.SHALLOW_OCEAN
	if relative_height < 24.0 or components.y < 0.72:
		return TerrainRegion.COAST
	if relative_height > definition.max_terrain_height_m * 0.72:
		return TerrainRegion.ALPINE
	if components.z > 0.24:
		return TerrainRegion.MOUNTAIN
	if components.w > 0.42:
		return TerrainRegion.PLATEAU
	return TerrainRegion.LOWLAND


## Natural height authority. Future edits compose outside this function:
## final_height = sample_base_height(direction) + terrain_edit_delta(position_m).
## Mesh/collision stay rebuildable; edits must invalidate affected jobs by revision.
func sample_base_height(direction: Vector3) -> float:
	return sample_height_m(direction)
