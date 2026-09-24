extends SceneTree
const Stage9Shape = preload("res://tests/planet/fixtures/stage9_shape.gd")
var checks := 0
var failures := 0
var reported := {}
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if not reported.has(message):
			push_error("RELIEF_TEST_FAILED: "+message)
			reported[message]=true
func direction_at(i: int, n: int) -> Vector3:
	var y := 1.0-2.0*(i+0.5)/n
	var r := sqrt(1.0-y*y)
	return Vector3(cos(i*2.399963229728653)*r,y,sin(i*2.399963229728653)*r)
func _run() -> void:
	var definition: PlanetDefinition = load("res://systems/planet/surface/data/test_planet_100km.tres")
	var base_definition: PlanetDefinition = definition.duplicate(true)
	base_definition.relief_enabled = false
	var shape := PlanetShape.new(definition)
	var legacy := Stage9Shape.new(definition)
	var copy := PlanetShape.new(definition.duplicate(true))
	var base := PlanetShape.new(base_definition)
	var alternate := PlanetShape.new(definition,PlanetGeology.new(definition,42))
	check(shape.geology.descriptors()==base.geology.descriptors(),"structural geology independent of final relief")
	var values := PackedFloat64Array()
	var before_land := 0
	var after_land := 0
	var coastal_changes := 0
	var changed_mask_range := Vector2(INF,-INF)
	var changed_old_range := Vector2(INF,-INF)
	var geological_changes := 0
	var max_delta := 0.0
	var peak := Vector3.ZERO
	var highest := -INF
	var plains := 0
	var plain_step := 0.0
	var mountain_samples := 0
	var curvature_old := 0.0
	var curvature_new := 0.0
	for i in range(8192):
		var d := direction_at(i,8192)
		var old := legacy.sample_components(d)
		var c := shape.sample_continental_components(d)
		var current := shape.sample_components(d)
		values.append(current.x)
		check(current.is_finite() and current.x>=-350 and current.x<=definition.natural_max_height_m(),"finite bounded natural height")
		check(c.y==old.y and current.y==old.y,"continental land mask preserved exactly")
		check(current==copy.sample_components(d),"independent deterministic instance")
		check((c.x>0)==(current.x>0),"relief cannot redraw continental coastline")
		check(c==alternate.sample_continental_components(d),"geology cannot change continents")
		if c.x<=0: check(current.x==c.x,"ocean unaffected by terrestrial relief")
		if (old.x>0)!=(current.x>0):
			coastal_changes+=1
			changed_mask_range=Vector2(minf(changed_mask_range.x,old.y),maxf(changed_mask_range.y,old.y))
			changed_old_range=Vector2(minf(changed_old_range.x,old.x),maxf(changed_old_range.y,old.x))
			check(absf(old.x)<30 and absf(current.x)<30,"coast changes confined to old transition")
		before_land+=int(old.x>0)
		after_land+=int(current.x>0)
		geological_changes+=int(absf(current.x-alternate.sample_height_m(d))>1)
		max_delta=maxf(max_delta,absf(current.x-old.x))
		if current.x>highest:
			highest=current.x
			peak=d
		var tangent := d.cross(Vector3.UP).normalized()
		if old.x>80 and current.x>25 and current.z<0.01 and current.w<0.01:
			plains+=1
			plain_step=maxf(plain_step,absf(shape.sample_height_m((d+tangent*20.0/50000.0).normalized())-current.x))
		if current.z>0.25:
			mountain_samples+=1
			var qa := (d-tangent*150.0/50000.0).normalized()
			var qb := (d+tangent*150.0/50000.0).normalized()
			curvature_old+=pow(legacy.sample_height_m(qa)-2*old.x+legacy.sample_height_m(qb),2)
			curvature_new+=pow(shape.sample_height_m(qa)-2*current.x+shape.sample_height_m(qb),2)
	for i in range(8191,-1,-1):
		check(values[i]==shape.sample_height_m(direction_at(i,8192)),"query order independent")
	check(coastal_changes==0 and before_land==after_land,"exact land/ocean sign preservation")
	check(geological_changes>500,"geology causally drives relief")
	check(plains>500 and plain_step<3.0,"substantial smooth usable plains")
	check(highest>300 and max_delta>200,"old terrestrial relief replaced")
	check(mountain_samples>=32 and curvature_new>curvature_old,"regional structure at geological chains")
	_test_structural_forms(definition,peak)
	_test_faces(shape)
	_test_meshes(definition,peak)
	_test_consumers(definition,base_definition,shape)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(values.to_byte_array())
	print("RELIEF fingerprint=",hash.finish().hex_encode())
	print("RELIEF_METRICS ",JSON.stringify({"land_before":before_land,"land_after":after_land,"changed_mask_range":str(changed_mask_range),"changed_old_range":str(changed_old_range),"coastal_changes":coastal_changes,"geological_changes":geological_changes,"max_delta_m":max_delta,"highest_m":highest,"plains":plains,"plain_max_step_20m":plain_step,"mountain_samples":mountain_samples,"mountain_curvature_ratio":sqrt(curvature_new/maxf(curvature_old,0.00001)),"peak":[peak.x,peak.y,peak.z]}))
	print("RELIEF checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

# Controlled descriptors isolate causality from random province overlap.
func _test_structural_forms(definition: PlanetDefinition, center: Vector3) -> void:
	var geology := PlanetGeology.new(definition)
	var p := PlanetGeology.Province.new()
	p.center=center
	p.axis=center.cross(Vector3.UP).normalized()
	p.side=center.cross(p.axis).normalized()
	p.radius=0.23
	p.age=0.2
	p.phase=0
	p.kind=PlanetGeology.Type.OROGEN
	geology._provinces.assign([p])
	geology._buckets.clear()
	geology._build_index()
	var relief := TerrainRelief.new(definition)
	var flat := Vector4(150,1,300,1)
	var along := (center+p.axis*0.07).normalized()
	var across := (center+p.side*0.07).normalized()
	check(relief.sample(along,flat,geology).x>relief.sample(across,flat,geology).x+70,"oriented elongated range")
	var side := (center+p.side*0.012).normalized()
	var young_ratio := (relief.sample(side,flat,geology).x-150)/(relief.sample(center,flat,geology).x-150)
	p.age=0.8
	var old_ratio := (relief.sample(side,flat,geology).x-150)/(relief.sample(center,flat,geology).x-150)
	check(old_ratio>young_ratio,"mature crests broader than young crests")
	p.kind=PlanetGeology.Type.PLATEAU
	var plateau := relief.sample(center,flat,geology).x
	p.kind=PlanetGeology.Type.SEDIMENTARY
	var basin := relief.sample(center,flat,geology).x
	check(plateau>230 and basin<125,"high structural plateau / low sedimentary basin")
	p.kind=PlanetGeology.Type.IGNEOUS
	check(relief.sample(center,flat,geology).x>relief.sample(along,flat,geology).x+50,"localized igneous structure")

func _test_faces(shape: PlanetShape) -> void:
	for face in range(6):
		for edge in range(4):
			for i in range(33):
				var t := i/32.0
				var uv := Vector2(t,0) if edge==0 else (Vector2(1,t) if edge==1 else (Vector2(t,1) if edge==2 else Vector2(0,t)))
				var d := CubeSphereMapping.face_uv_to_direction(face,uv)
				var reference := shape.sample_height_m(d)
				var normal := PlanetChunkBuilder.surface_normal(shape,d)
				for other in range(6):
					var axes := CubeSphereMapping.face_axes(other)
					var divisor := d.dot(CubeSphereMapping.face_normal(other))
					if divisor<=0: continue
					var q := d/divisor
					var other_uv := Vector2(q.dot(axes[0]),q.dot(axes[1]))*0.5+Vector2(0.5,0.5)
					if other_uv.x<0 or other_uv.y<0 or other_uv.x>1 or other_uv.y>1: continue
					var same := CubeSphereMapping.face_uv_to_direction(other,other_uv)
					check(absf(reference-shape.sample_height_m(same))<0.02,"12 edges / 8 corners heights")
					check(normal.distance_to(PlanetChunkBuilder.surface_normal(shape,same))<0.025,"face normal continuity")

func _test_meshes(definition: PlanetDefinition, peak: Vector3) -> void:
	var address := CubeSphereMapping.direction_to_face_uv(peak)
	var shape := PlanetShape.new(definition)
	var fine_errors := []
	var common_uv: Vector2 = (address.uv*1024.0).floor()/1024.0
	var common_point := Vector3.ZERO
	var common_normal := Vector3.ZERO
	for level in [6,7,8,9]:
		var n: int = 1<<level
		var cell := Vector2i((common_uv*float(n)).floor())
		var builder := PlanetChunkBuilder.new(definition,address.face,level,cell,17)
		var other := PlanetChunkBuilder.new(definition,address.face,level,cell,17)
		var task_a := WorkerThreadPool.add_task(builder.build)
		var task_b := WorkerThreadPool.add_task(other.build)
		WorkerThreadPool.wait_for_task_completion(task_a)
		WorkerThreadPool.wait_for_task_completion(task_b)
		var result := builder.result
		var vertices: PackedVector3Array = result.arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = result.arrays[Mesh.ARRAY_NORMAL]
		var local_vertex := Vector2i(((common_uv*float(n)-Vector2(cell))*16.0).round())
		var common_index := local_vertex.x+local_vertex.y*17
		if level==6:
			common_point=vertices[common_index]
			common_normal=normals[common_index]
		check(vertices[common_index]==common_point and normals[common_index]==common_normal,"exact shared direction across LOD 6/7/8/9")
		check(vertices==other.result.arrays[Mesh.ARRAY_VERTEX],"concurrent worker determinism")
		for i in range(vertices.size()):
			check(result.bounds.grow(0.01).has_point(vertices[i]),"bounds include mesh and skirts")
			check(normals[i].is_finite() and absf(normals[i].length()-1.0)<0.00001 and normals[i].dot(vertices[i])>0,"physical outward normal")
		for y in range(17):
			for x in range(17):
				var d := CubeSphereMapping.face_uv_to_direction(address.face,(Vector2(cell)+Vector2(x,y)/16.0)/float(n))
				check(absf(vertices[x+y*17].length()-50000.0-shape.sample_base_height(d))<0.02,"same natural function LOD 6/7/8/9")
		var indices: PackedInt32Array = result.arrays[Mesh.ARRAY_INDEX]
		for i in range(0,16*16*6,3):
			var a := vertices[indices[i]]
			var b := vertices[indices[i+1]]
			var c := vertices[indices[i+2]]
			check((b-a).cross(c-a).dot(a)<0,"winding")
		# Quarter points not used by the builder: verify its conservative SSE.
		var maximum := 0.0
		for y in range(16):
			for x in range(16):
				for f in [0.25,0.75]:
					var d := CubeSphereMapping.face_uv_to_direction(address.face,(Vector2(cell)+(Vector2(x,y)+Vector2(f,f))/16.0)/float(n))
					var actual := shape.point_on_planet(d)
					var estimate := vertices[x+y*17].lerp(vertices[x+1+(y+1)*17],f)
					maximum=maxf(maximum,actual.distance_to(estimate))
					check(result.bounds.grow(0.01).has_point(actual),"bounds include unsampled terrain")
		check(maximum<=result.error_m+0.05,"SSE covers independent quarter-point error")
		fine_errors.append(maximum)
	# Global terrain resolution is ~8–12 m, not a Mining Zone. Bound the
	# interpolation error relative to the actual surface segment, independently
	# of the builder SSE, and require convergence at every refinement.
	var d0 := CubeSphereMapping.face_uv_to_direction(address.face,common_uv)
	var d1 := CubeSphereMapping.face_uv_to_direction(address.face,common_uv+Vector2(1.0/(512*16),0))
	var near_spacing := definition.radius_m*d0.distance_to(d1)
	for i in range(1,4):
		check(fine_errors[i]<fine_errors[i-1],"error decreases at each refinement")
	check(fine_errors[3]<fine_errors[0]*0.1 and fine_errors[3]<near_spacing*0.25,"near error below quarter of physical cell and 10% of LOD6")
	print("RELIEF_LOD_ERROR ",fine_errors)

func _test_consumers(definition: PlanetDefinition, old_definition: PlanetDefinition, shape: PlanetShape) -> void:
	var climate := PlanetClimate.new(definition)
	var old_climate := PlanetClimate.new(old_definition)
	var geology := PlanetGeology.new(definition)
	var biomes := PlanetBiomes.new(definition,climate,geology)
	var changed_temperature := 0
	for i in range(512):
		var d := direction_at(i,512)
		var terrain := shape.sample_components(d)
		var current := climate.sample(d)
		check(absf(current.altitude_m-(terrain.x-definition.sea_level_m))<0.001,"climate uses refined natural height")
		changed_temperature+=int(absf(current.temperature_c-old_climate.sample(d).temperature_c)>0.001)
		var a := biomes.sample(d)
		var b := PlanetBiomeSample.new()
		biomes.sample_with_context_into(d,terrain,current,b)
		check(a.weights==b.weights and a.dominant==b.dominant,"biome consumes current topography/climate")
	check(changed_temperature>20,"derived climate rebuilt after relief")


