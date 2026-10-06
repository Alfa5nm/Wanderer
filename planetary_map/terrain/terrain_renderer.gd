class_name PlanetTerrainRenderer
extends Node3D

signal settled
signal boot_ready
var roots_ready := false
const SEGMENTS := 24
const MAX_PATCHES := 150
const MAX_LEVEL := 17
var service: PlanetSurfaceService
var camera: Camera3D
var patches: Dictionary = {}
var desired: Dictionary = {}
var pending: Array[Dictionary] = []
var job: Dictionary
var worker: Thread
var timer := 0.0
var base_material: ShaderMaterial
var last_camera := Vector3.INF
var generation := 0
var uploads := 0
var error_cache: Dictionary = {}
var leaf_lookup: Dictionary = {}
var choose_max_ms := 0.0
var choosing := false
var planning_view := Vector3.ZERO
var planning_inverse := Basis.IDENTITY
var planning_size := Vector2.ONE
var planning_fov := 42.0
var surface_revision := 0
var rendered_revision := -1
var origins: Dictionary = {}
var imagery_age: Dictionary = {}
var visual_settings: PlanetVisualSettings
var atmosphere: MeshInstance3D

static func direction(face: int,u: float,v: float) -> Vector3:
	match face:
		0: return Vector3(1,v,-u).normalized()
		1: return Vector3(-1,v,u).normalized()
		2: return Vector3(u,1,-v).normalized()
		3: return Vector3(u,-1,v).normalized()
		4: return Vector3(u,v,1).normalized()
		_: return Vector3(-u,v,-1).normalized()

static func face_uv(point: Vector3) -> Vector3:
	var a := point.abs()
	if a.x>=a.y and a.x>=a.z:
		return Vector3(0,-point.z/a.x,point.y/a.x) if point.x>0 else Vector3(1,point.z/a.x,point.y/a.x)
	if a.y>=a.z:
		return Vector3(2,point.x/a.y,-point.z/a.y) if point.y>0 else Vector3(3,point.x/a.y,point.z/a.y)
	return Vector3(4,point.x/a.z,point.y/a.z) if point.z>0 else Vector3(5,-point.x/a.z,point.y/a.z)

static func tile_key(tile: Dictionary) -> String:
	return "%d/%d/%d/%d" % [tile.face,tile.level,tile.x,tile.y]

func _ready() -> void:
	base_material = ShaderMaterial.new()
	base_material.shader = load("res://planetary_map/terrain/terrain.gdshader")
	set_albedo(load("res://planetary_map/assets/mars_viking_4k.jpg"))
	service.data_changed.connect(func(): surface_revision+=1; refresh_imagery())
	refresh_imagery()
	set_as_top_level(true)
	global_position=Vector3.ZERO
	scale=Vector3.ONE*PlanetCameraRig.RENDER_SCALE
	atmosphere = MeshInstance3D.new()
	if visual_settings==null: visual_settings=PlanetVisualSettings.new()
	var quad := QuadMesh.new()
	quad.size=Vector2(2,2)
	atmosphere.mesh=quad
	atmosphere.extra_cull_margin=100000
	var material := ShaderMaterial.new()
	material.shader=load("res://planetary_map/terrain/atmosphere.gdshader")
	material.set_shader_parameter("sun_direction",visual_settings.sun_direction)
	material.set_shader_parameter("render_scale",PlanetCameraRig.RENDER_SCALE*service.radius)
	material.set_shader_parameter("physical_radius_m",service.physical_radius_m)
	visual_settings.atmosphere.apply(material)
	material.set_shader_parameter("shell_height",visual_settings.atmosphere.top_height_m/service.physical_radius_m)
	material.render_priority=100
	atmosphere.material_override=material
	atmosphere.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(atmosphere)
	choose_tiles()

func set_albedo(texture: Texture2D) -> void:
	base_material.set_shader_parameter("has_albedo",texture != null)
	if texture != null: base_material.set_shader_parameter("global_albedo",texture)
	for patch in patches.values():
		patch.material_override.set_shader_parameter("has_albedo",texture != null)
		if texture != null: patch.material_override.set_shader_parameter("global_albedo",texture)

func refresh_imagery() -> void:
	var images: Array[PlanetDataset] = []
	for data in service.datasets:
		if data.kind == "imagery" and data.texture != null: images.append(data)
	var center := PlanetCoordinates.local_to_lat_lon(service.render_origin)
	var span := maxf(0.05,(service.render_origin.length()/service.radius-1.0)*160.0)
	var relevant: Array[PlanetDataset] = []
	var backgrounds: Array[PlanetDataset] = []
	for data in images:
		var nearest := Vector2(clampf(center.y,data.bounds.position.x,data.bounds.end.x),clampf(center.x,data.bounds.position.y,data.bounds.end.y))
		if nearest.distance_to(Vector2(center.y,center.x))>span: continue
		if data.metadata.get("role","")=="view_background": backgrounds.append(data)
		else: relevant.append(data)
	relevant.sort_custom(func(a: PlanetDataset,b: PlanetDataset): return a.prepared_spacing_m<b.prepared_spacing_m)
	backgrounds.sort_custom(func(a: PlanetDataset,b: PlanetDataset): return int(a.metadata.get("accepted_usec",0))<int(b.metadata.get("accepted_usec",0)))
	images.clear()
	# Retain previous surrounding atlas while the replacement fades in.
	for index in range(backgrounds.size()-1,-1,-1):
		if images.size()>=2: break
		images.append(backgrounds[index])
	for data in relevant:
		if images.size()>=5: break
		images.append(data)
	images.sort_custom(func(a: PlanetDataset,b: PlanetDataset): return a.prepared_spacing_m>b.prepared_spacing_m)
	for i in range(5):
		var image_parameter: String = ["regional_image","local_image","stream_image_0","stream_image_1","stream_image_2"][i]
		var bounds_parameter: String = ["regional_bounds","local_bounds","stream_bounds_0","stream_bounds_1","stream_bounds_2"][i]
		var data: PlanetDataset = images[i] if images.size()>i else null
		var bounds := Vector4.ZERO if data == null else Vector4(data.bounds.position.x,data.bounds.position.y,data.bounds.size.x,data.bounds.size.y)
		if data!=null and not imagery_age.has(data.id): imagery_age[data.id]=0.0
		base_material.set_meta("image_id_"+str(i),data.id if data!=null else "")
		for material in [base_material]+patches.values().map(func(patch): return patch.material_override):
			material.set_shader_parameter(bounds_parameter,bounds)
			material.set_shader_parameter(image_parameter,data.texture if data!=null else null)
			material.set_shader_parameter("image_opacity_"+str(i),minf(float(imagery_age.get(data.id,0))/0.65,1.0) if data!=null else 0.0)

func screen_error(tile: Dictionary) -> float:
	var key := tile_key(tile)
	if not error_cache.has(key): error_cache[key]=calculate_screen_error(tile)
	return error_cache[key]

func calculate_screen_error(tile: Dictionary) -> float:
	var count := pow(2.0,tile.level)
	var width := 2.0/count
	var center := direction(tile.face,-1+(tile.x+0.5)*width,-1+(tile.y+0.5)*width)*service.radius
	var view := planning_view
	var distance := maxf(view.distance_to(center)-width*service.radius*0.6,0.00001)
	if center.normalized().dot(view.normalized()) < service.radius/view.length()-width*1.5: return 0
	var local := planning_inverse*((center-view)*PlanetCameraRig.RENDER_SCALE)
	if local.z>=0: return 0
	var focal := planning_size.y/(2*tan(deg_to_rad(planning_fov)*0.5))
	var projection := planning_size*0.5+Vector2(local.x,-local.y)*focal/(-local.z)
	var pixel_radius := width*service.radius/distance*planning_size.y
	if not Rect2(Vector2.ZERO,planning_size).grow(pixel_radius).has_point(projection): return 0
	return width*service.radius/SEGMENTS/distance*focal

func choose_tiles() -> void:
	if choosing: return
	choosing=true
	planning_view=service.render_origin
	planning_inverse=camera.global_basis.inverse()
	planning_size=camera.get_viewport().get_visible_rect().size
	planning_fov=camera.fov
	var revision := surface_revision
	var started := Time.get_ticks_usec()
	var slice_started := started
	error_cache.clear()
	var leaves: Array[Dictionary] = []
	for face in 6: leaves.append({"face":face,"level":0,"x":0,"y":0})
	while leaves.size()+3<=MAX_PATCHES:
		if Time.get_ticks_usec()-slice_started>2000:
			choose_max_ms=maxf(choose_max_ms,float(Time.get_ticks_usec()-slice_started)/1000.0)
			await get_tree().process_frame
			if not is_inside_tree(): return
			slice_started=Time.get_ticks_usec()
		var best := -1
		var error := 3.5
		for i in leaves.size():
			var candidate: Dictionary = leaves[i]
			if candidate.level>=MAX_LEVEL: continue
			var value := screen_error(candidate)
			# Existing subdivisions retain a lower merge threshold.
			if not patches.has(tile_key(candidate)): value *= 1.15
			if value>error: best=i; error=value
		if best<0: break
		var parent: Dictionary = leaves.pop_at(best)
		for y in 2:
			for x in 2: leaves.append({"face":parent.face,"level":parent.level+1,"x":parent.x*2+x,"y":parent.y*2+y})
	leaf_lookup.clear()
	for leaf in leaves: leaf_lookup[tile_key(leaf)]=leaf
	# Balance across face boundaries; never leave a neighbour more than one level away.
	var balanced := false
	while not balanced:
		balanced = true
		for leaf in leaves.duplicate():
			if Time.get_ticks_usec()-slice_started>2000:
				choose_max_ms=maxf(choose_max_ms,float(Time.get_ticks_usec()-slice_started)/1000.0)
				await get_tree().process_frame
				if not is_inside_tree(): return
				slice_started=Time.get_ticks_usec()
			var width := 2.0/pow(2.0,leaf.level)
			for edge in [Vector2(-0.001,0.5),Vector2(1.001,0.5),Vector2(0.5,-0.001),Vector2(0.5,1.001)]:
				var probe := direction(leaf.face,-1+(leaf.x+edge.x)*width,-1+(leaf.y+edge.y)*width)
				var neighbor := indexed_leaf(probe)
				if not neighbor.is_empty() and neighbor.level<leaf.level-1:
					leaves.erase(neighbor)
					leaf_lookup.erase(tile_key(neighbor))
					for y in 2:
						for x in 2:
							var child := {"face":neighbor.face,"level":neighbor.level+1,"x":neighbor.x*2+x,"y":neighbor.y*2+y}
							leaves.append(child)
							leaf_lookup[tile_key(child)]=child
					balanced = false
					break
			if not balanced: break
	desired.clear()
	for leaf in leaves:
		leaf["edges"] = coarse_edges(leaf,leaves)
		desired[tile_key(leaf)] = leaf
	pending.clear()
	for key in desired:
		if not patches.has(key) or rendered_revision != surface_revision:
			pending.append(desired[key])
	pending.sort_custom(func(a: Dictionary,b: Dictionary): return screen_error(a)>screen_error(b))
	# Keep a complete low-detail planet available through interrupted refinements.
	for face in range(5,-1,-1):
		var root_tile := {"face":face,"level":0,"x":0,"y":0,"edges":[false,false,false,false]}
		var root_key := tile_key(root_tile)
		if not patches.has(root_key):
			pending = pending.filter(func(tile: Dictionary): return tile_key(tile)!=root_key)
			pending.push_front(root_tile)
	generation+=1
	update_frontier()
	last_camera = planning_view
	rendered_revision = revision
	choosing=false
	choose_max_ms=maxf(choose_max_ms,float(Time.get_ticks_usec()-slice_started)/1000.0)

static func find_leaf(probe: Vector3,leaves: Array[Dictionary]) -> Dictionary:
	var face := face_uv(probe)
	for leaf in leaves:
		if leaf.face != int(face.x): continue
		var n := pow(2.0,leaf.level)
		if int(clampf((face.y+1)*0.5*n,0,n-1))==leaf.x and int(clampf((face.z+1)*0.5*n,0,n-1))==leaf.y: return leaf
	return {}

func indexed_leaf(probe: Vector3) -> Dictionary:
	var face := face_uv(probe)
	for level in range(MAX_LEVEL+1):
		var n := 1<<level
		var key := "%d/%d/%d/%d" % [int(face.x),level,int(clampf((face.y+1)*0.5*n,0,n-1)),int(clampf((face.z+1)*0.5*n,0,n-1))]
		if leaf_lookup.has(key): return leaf_lookup[key]
	return {}

func coarse_edges(tile: Dictionary,leaves: Array[Dictionary]) -> Array[bool]:
	var result: Array[bool] = []
	var width := 2.0/pow(2.0,tile.level)
	for edge in [Vector2(-0.001,0.5),Vector2(1.001,0.5),Vector2(0.5,-0.001),Vector2(0.5,1.001)]:
		var neighbor := indexed_leaf(direction(tile.face,-1+(tile.x+edge.x)*width,-1+(tile.y+edge.y)*width))
		result.append(not neighbor.is_empty() and neighbor.level<tile.level)
	return result

func build_patch(tile: Dictionary) -> Dictionary:
	var width := 2.0/pow(2.0,tile.level)
	var center_dir := direction(tile.face,-1+(tile.x+0.5)*width,-1+(tile.y+0.5)*width)
	var ll := PlanetCoordinates.local_to_lat_lon(center_dir)
	var origin := service.position_at(ll.x,ll.y)
	var origin64 := service.position64(ll.x,ll.y)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var step := maxf(0.00001,rad_to_deg(width/SEGMENTS)*0.4)
	for y in range(SEGMENTS+1):
		for x in range(SEGMENTS+1):
			var p := direction(tile.face,-1+(tile.x+float(x)/SEGMENTS)*width,-1+(tile.y+float(y)/SEGMENTS)*width)
			ll = PlanetCoordinates.local_to_lat_lon(p)
			vertices.append(PlanetSurfaceService.relative64(service.position64(ll.x,ll.y),origin64))
			normals.append(service.normal_at(ll.x,ll.y,step))
			uv.append(PlanetCoordinates.lat_lon_to_uv(ll.x,ll.y))
	# Stitch odd boundary vertices to the coarse neighbour's straight edges.
	for i in range(1,SEGMENTS,2):
		for edge in 4:
			if not tile.edges[edge]: continue
			var index := i*(SEGMENTS+1) if edge==0 else i*(SEGMENTS+1)+SEGMENTS
			var stride := SEGMENTS+1
			if edge>=2: index=i+(SEGMENTS*(SEGMENTS+1) if edge==3 else 0); stride=1
			vertices[index] = (vertices[index-stride]+vertices[index+stride])*0.5
	for y in range(SEGMENTS+1):
		for x in range(SEGMENTS+1):
			var index := y*(SEGMENTS+1)+x
			var x0 := x-x%2
			var y0 := y-y%2
			var x1 := mini(x0+2,SEGMENTS)
			var y1 := mini(y0+2,SEGMENTS)
			var a := vertices[y0*(SEGMENTS+1)+x0]
			var b := vertices[y0*(SEGMENTS+1)+x1]
			var c := vertices[y1*(SEGMENTS+1)+x0]
			var d := vertices[y1*(SEGMENTS+1)+x1]
			var parent := a.lerp(b,float(x-x0)/2).lerp(c.lerp(d,float(x-x0)/2),float(y-y0)/2)
			var delta := (parent-vertices[index])/(width*service.radius)
			colors.append(Color(delta.x+0.5,delta.y+0.5,delta.z+0.5,1))
	for y in SEGMENTS:
		for x in SEGMENTS:
			var a := y*(SEGMENTS+1)+x
			indices.append_array(PackedInt32Array([a,a+SEGMENTS+1,a+1,a+1,a+SEGMENTS+1,a+SEGMENTS+2]))
	# Fix UV interpolation across the date line locally, using repeat wrapping.
	var minimum := 1.0
	var maximum := 0.0
	for p in uv: minimum=minf(minimum,p.x); maximum=maxf(maximum,p.x)
	if maximum-minimum>0.5:
		for i in uv.size():
			if uv[i].x<0.5: uv[i].x+=1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uv
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_INDEX]=indices
	return {"arrays":arrays,"origin":origin,"origin64":origin64,"extent":width*service.radius,"tile":tile,"generation":generation}

func sync_view() -> void:
	var detail := 1.0-smoothstep(0.05,0.20,maxf(0,service.render_origin.length()/service.radius-1.0))
	atmosphere.global_position=Vector3.ZERO
	atmosphere.material_override.set_shader_parameter("eye_origin",service.render_origin/service.radius)
	var geo := PlanetCoordinates.local_to_lat_lon(service.render_origin)
	var ground_radius := float(service.sample(geo.x,geo.y).radial_m)/service.physical_radius_m if service.render_origin.length()/service.radius<1.06 else 1.0
	atmosphere.material_override.set_shader_parameter("ground_radius",ground_radius)
	for key in patches:
		patches[key].material_override.set_shader_parameter("regional_detail",detail)
		patches[key].position=PlanetSurfaceService.relative64(origins[key],service.render_origin64)

func _process(dt: float) -> void:
	timer+=dt
	for id in imagery_age: imagery_age[id]=minf(float(imagery_age[id])+dt,1.0)
	for i in 5:
		var opacity := minf(float(imagery_age.get(base_material.get_meta("image_id_"+str(i),""),0))/0.65,1.0)
		base_material.set_shader_parameter("image_opacity_"+str(i),opacity)
		for patch in patches.values(): patch.material_override.set_shader_parameter("image_opacity_"+str(i),opacity)
	base_material.set_shader_parameter("regional_detail",1.0-smoothstep(0.05,0.20,maxf(0,service.render_origin.length()/service.radius-1.0)))
	sync_view()
	if not choosing and timer>0.35 and (service.render_origin.distance_to(last_camera)>service.radius*0.00002 or rendered_revision!=surface_revision):
		timer=0
		choose_tiles()
	if worker!=null and not worker.is_alive():
		var result: Dictionary = worker.wait_to_finish()
		worker=null
		var key := tile_key(result.tile)
		if desired.has(key) or result.tile.level==0:
			if patches.has(key): patches[key].queue_free()
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,result.arrays)
			var patch := MeshInstance3D.new()
			patch.mesh=mesh
			patch.position=PlanetSurfaceService.relative64(result.origin64,service.render_origin64)
			patch.material_override=base_material.duplicate()
			patch.material_override.set_shader_parameter("patch_extent",result.extent)
			patch.material_override.set_shader_parameter("morph",0.0)
			var tile_data := PlanetTerrainTile.new()
			tile_data.face=result.tile.face
			tile_data.level=result.tile.level
			tile_data.x=result.tile.x
			tile_data.y=result.tile.y
			var coordinates := PlanetCoordinates.local_to_lat_lon(result.origin)
			var source := service.sample(coordinates.x,coordinates.y)
			tile_data.source_spacing_m=source.get("spacing_m",926)
			tile_data.geometric_error_m=result.extent*service.physical_radius_m/SEGMENTS
			tile_data.dataset_ids=PackedStringArray([source.get("source","MOLA")])
			patch.set_meta("terrain_tile",tile_data)
			add_child(patch)
			patches[key]=patch
			origins[key]=result.origin64
			create_tween().tween_property(patch.material_override,"shader_parameter/morph",1.0,0.35)
			uploads+=1
			update_frontier()
			if not roots_ready:
				var complete := true
				for face in 6: complete = complete and patches.has("%d/0/0/0" % face)
				if complete:
					roots_ready=true
					boot_ready.emit()
	if worker==null and not pending.is_empty():
		job=pending.pop_front()
		worker=Thread.new()
		worker.start(build_patch.bind(job.duplicate(true)))
	if not choosing and pending.is_empty() and worker==null:
		# Parents are removed only after the entire replacement frontier is ready.
		for key in patches.keys():
			if not desired.has(key) and int(str(key).split("/")[1])>0: patches[key].queue_free(); patches.erase(key); origins.erase(key)
		update_frontier()
		settled.emit()

# Draw a complete frontier: parents cover pending children, without overlapping them.
func update_frontier() -> void:
	var branches: Dictionary = {}
	for key in patches:
		var parts := str(key).split("/")
		var tile := {"face":int(parts[0]),"level":int(parts[1]),"x":int(parts[2]),"y":int(parts[3])}
		while tile.level>0:
			tile.level-=1; tile.x=int(tile.x/2); tile.y=int(tile.y/2)
			branches[tile_key(tile)]=true
	var visible_keys: Array[String] = []
	for face in 6:
		visible_keys.append_array(ready_frontier({"face":face,"level":0,"x":0,"y":0},branches))
	for key in patches: patches[key].visible=visible_keys.has(key)

func ready_frontier(tile: Dictionary,branches: Dictionary) -> Array[String]:
	var key := tile_key(tile)
	if desired.has(key) and patches.has(key): return [key]
	if branches.has(key):
		var children: Array[String] = []
		var complete := true
		for y in 2:
			for x in 2:
				var available := ready_frontier({"face":tile.face,"level":tile.level+1,"x":tile.x*2+x,"y":tile.y*2+y},branches)
				complete=complete and not available.is_empty()
				children.append_array(available)
		if complete: return children
	var fallback: Array[String] = []
	if patches.has(key): fallback.append(key)
	return fallback

func _exit_tree() -> void:
	if worker!=null: worker.wait_to_finish(); worker=null
