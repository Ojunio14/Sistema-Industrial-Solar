class_name ContinentalShape
extends RefCounted
## Continental distribution only. The donor continent/warp/coast expressions
## are preserved exactly. Donor fields below reconstruct ONLY the shoreline
## envelope (including shallow submerged pockets), never inland relief.
## A land mask alone is insufficient: old hills/ridges also crossed sea level.
var definition: PlanetDefinition
var _continent := FastNoiseLite.new()
var _warp := FastNoiseLite.new()

var _hill_noise := FastNoiseLite.new()
var _plateau_noise := FastNoiseLite.new()
var _mountain_noise := FastNoiseLite.new()
var _belt_noise := FastNoiseLite.new()
var _valley_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()

func _init(source: PlanetDefinition) -> void:
	definition = source
	_configure(_continent,source.seed,5)
	_configure(_warp,source.seed+157,3)
	for settings in [[_hill_noise,409,4,0.48],[_plateau_noise,673,3,0.52],
		[_mountain_noise,1013,5,0.48],[_belt_noise,1459,3,0.5],
		[_valley_noise,2027,4,0.5],[_detail_noise,2521,3,0.45]]:
		_configure(settings[0],source.seed+int(settings[1]),int(settings[2]))
		settings[0].fractal_gain=settings[3]
	_mountain_noise.fractal_type=FastNoiseLite.FRACTAL_RIDGED

static func _configure(noise: FastNoiseLite, seed: int, octaves: int) -> void:
	noise.seed=seed
	noise.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency=1.0
	noise.fractal_type=FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves=octaves
	noise.fractal_gain=0.5

## x=continental base height, y=exact donor land mask,
## z=shore clearance proxy (legacy coast field), w=interior. No inland relief.
func sample(direction: Vector3) -> Vector4:
	assert(not direction.is_zero_approx())
	var p := direction.normalized()
	var warp_scale := definition.continent_warp_scale
	var warp := Vector3(
		_warp.get_noise_3dv(p*warp_scale+Vector3(19.1,3.7,11.8)),
		_warp.get_noise_3dv(p*warp_scale+Vector3(-5.2,17.4,2.3)),
		_warp.get_noise_3dv(p*warp_scale+Vector3(7.6,-9.8,23.5)))
	var warped := (p+warp*definition.continent_warp_strength).normalized()
	var continental := _continent.get_noise_3dv(warped*definition.continent_scale)
	var threshold := definition.continent_threshold
	var coast := definition.coast_blend
	var land := smoothstep(threshold-coast,threshold+coast,continental)
	var interior := smoothstep(0.3,0.92,land)
	var elevation := clampf((continental-threshold)/maxf(1.0-threshold,0.01),0.0,1.0)
	var shelf := smoothstep(threshold-coast*2.5,threshold-coast*0.1,continental)
	var floor_height := lerpf(-definition.ocean_depth_m,-definition.ocean_depth_m*0.16,shelf)
	var lowland := 18.0+pow(elevation,0.72)*definition.lowland_height_m
	var shoreline := _shoreline_height(p,warped,land,interior,elevation,floor_height)
	var shore := shoreline.x
	# Reconstruct the exact old zero contour. Beyond 45 m, discard ALL old
	# terrestrial relief: the substrate comes only from continental elevation.
	var height := lerpf(shore,lowland,smoothstep(0.0,45.0,shore))
	return Vector4(height+definition.sea_level_m,land,shoreline.y,interior)

## Compatibility of the approved water/land contour, not a terrain layer.
## Only heights below 45 m survive the coastal envelope in sample().
func _shoreline_height(p: Vector3, warped: Vector3, land: float, interior: float,
		continent_height: float, ocean_floor: float) -> Vector2:
	var hill_raw := _hill_noise.get_noise_3dv(warped * definition.hill_scale) * 0.5 + 0.5
	var hills := (hill_raw - 0.5) * 2.0 * definition.hill_height_m
	var lowlands := 18.0 + pow(continent_height, 0.72) * definition.lowland_height_m + hills

	var plateau_raw := _plateau_noise.get_noise_3dv(warped * definition.plateau_scale) * 0.5 + 0.5
	var plateau_mask := smoothstep(0.56, 0.78, plateau_raw) * interior
	var plateau_height := definition.plateau_height_m * plateau_mask
	var unstepped := lowlands + plateau_height
	var smooth_unstepped := unstepped
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
	# The old quantized terrace is required only for the exact zero contour.
	# Never feed its steps into the relief amplitude envelope.
	var smooth_height := lerpf(ocean_floor,maxf(land_height+smooth_unstepped-unstepped,-8.0),land)
	return Vector2(clampf(height,-definition.ocean_depth_m,definition.max_terrain_height_m),smooth_height)
