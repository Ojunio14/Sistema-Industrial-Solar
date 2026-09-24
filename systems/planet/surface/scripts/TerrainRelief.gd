class_name TerrainRelief
extends RefCounted
## Terrestrial relief from oriented geological descriptors. Never reads biome,
## climate, a mesh, LOD or final-height-dependent geological classification.
var _regional := FastNoiseLite.new()
var _meso := FastNoiseLite.new()
var _radius: float
var _sea: float
var _chain_height: float
var _plateau_height: float
var _enabled: bool

func _init(definition: PlanetDefinition) -> void:
	_radius=definition.radius_m
	_sea=definition.sea_level_m
	_chain_height=definition.mountain_height_m*2.8
	_plateau_height=definition.plateau_height_m*1.5
	_enabled=definition.relief_enabled
	for pair in [[_regional,3109],[_meso,4211]]:
		var noise: FastNoiseLite=pair[0]
		noise.seed=definition.seed+int(pair[1])
		noise.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_type=FastNoiseLite.FRACTAL_NONE
		noise.frequency=1.0

## Continuous 3D height and physical masks. The caller owns the geological
## context; this object keeps no back-reference, avoiding a RefCounted cycle.
func sample(direction: Vector3, continental: Vector4, geology: PlanetGeology) -> Vector4:
	var altitude := continental.x-_sea
	if altitude<=0.0 or not _enabled:
		return Vector4(continental.x,continental.y,0.0,0.0)
	var d := direction.normalized()
	var coast := smoothstep(0.0,40.0,altitude)*smoothstep(0.0,250.0,continental.z)
	var chains := 0.0
	var chain_weight := 0.0
	var plateaus := 0.0
	var plateau_weight := 0.0
	var igneous := 0.0
	var igneous_weight := 0.0
	var basin := 0.0
	var old_interior := 0.0
	for province: PlanetGeology.Province in geology.relief_candidates(d):
		var chord2 := 2.0-2.0*clampf(d.dot(province.center),-1.0,1.0)
		var radius2 := province.radius*province.radius
		if chord2>=radius2: continue
		var radial := sqrt(maxf(0.0,chord2/radius2))
		var support := 1.0-smoothstep(0.72,1.0,radial)
		var along := d.dot(province.axis)*_radius
		var across := d.dot(province.side)*_radius
		var extent := province.radius*_radius
		match province.kind:
			PlanetGeology.Type.OROGEN:
				var width := extent*lerpf(0.28,0.48,province.age)
				var bend := sin(along/3300.0+province.phase)*width*0.18
				bend += sin(along/1100.0+province.phase)*width*0.055
				var cross_distance := across-bend
				var end := 1.0-smoothstep(0.55,1.0,absf(along)/extent)
				var apron := 1.0-smoothstep(0.20,1.0,absf(cross_distance)/width)
				var weight := support*end*apron
				if weight<=0.0: continue
				# Young belts have narrow crests; mature belts broad shoulders.
				var crest_width := width*lerpf(0.14,0.38,province.age)
				var crest := exp(-pow(sqrt(cross_distance*cross_distance+10000.0)/crest_width,1.45))
				var secondary := exp(-pow((cross_distance-width*0.43)/(crest_width*0.75),2.0))*0.28
				var shoulder := exp(-pow((cross_distance+width*0.42)/(width*0.35),2.0))*0.15
				var grouping := 0.73+0.27*_regional.get_noise_2d(along/1800.0,province.phase)
				var channels := _meso.get_noise_2d(along/480.0,across/650.0+province.phase)
				var meso := (0.36-sqrt(channels*channels+0.09))*450.0*(1.0-province.age*0.65)
				chains += weight*((crest+secondary+shoulder)/1.43*_chain_height*grouping+meso)
				chain_weight += weight
			PlanetGeology.Type.PLATEAU:
				var top := 1.0-smoothstep(0.48,1.0,radial)
				plateaus += top*(_plateau_height+_regional.get_noise_2d(along/2800.0,across/2800.0)*12.0)
				plateau_weight += top
			PlanetGeology.Type.IGNEOUS:
				var cone := exp(-pow(radial/0.32,2.0))*230.0
				var rim := exp(-pow((radial-0.20)/0.08,2.0))*45.0
				igneous += support*(cone+rim)
				igneous_weight += support
			PlanetGeology.Type.SEDIMENTARY, PlanetGeology.Type.CLOSED_BASIN:
				basin += (1.0-smoothstep(0.25,1.0,radial))*0.8
			PlanetGeology.Type.CRATON:
				old_interior += (1.0-radial*radial)*province.age
	# Soft saturation keeps intersecting geological regions continuous and
	# prevents an accidental sum of overlapping belts producing giant spikes.
	chains *= _coverage(chain_weight)
	plateaus *= _coverage(plateau_weight)
	igneous *= _coverage(igneous_weight)
	var mountain := 1.0-exp(-chain_weight)
	var plateau := 1.0-exp(-plateau_weight)
	var low_basin := 1.0-exp(-basin)
	var mature := 1.0-exp(-old_interior)
	var hills := _regional.get_noise_3dv(d*_radius/3200.0)*lerpf(22.0,4.0,mature)
	hills *= (1.0-low_basin)*(1.0-plateau)
	var base_land := lerpf(altitude,25.0,low_basin*0.75)
	var height := altitude+coast*(base_land-altitude+hills+chains+plateaus+igneous)
	# At low coastal altitudes the envelope already fades; this floor preserves
	# the continental land sign even for unusual configurations/seeds.
	height=maxf(height,altitude*0.15)
	return Vector4(_sea+height,continental.y,mountain*coast,plateau*coast)

static func _coverage(weight: float) -> float:
	return (1.0-exp(-weight))/weight if weight>0.00001 else 1.0

## No LOD-specific terrain. This missing-detail allowance only affects SSE.
static func unresolved_error(spacing_m: float) -> float:
	return 160.0*smoothstep(20.0,600.0,spacing_m)

