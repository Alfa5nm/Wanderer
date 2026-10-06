class_name MarsWheelTracks
extends Node3D

# One rolling height/compaction mask shared by all six wheels. Render-only.
const SPAN := 16.0
const PIXELS := 1024
const TILE := 4.0
const CELLS := 128
const NEUTRAL := 128.0/255.0
var world: Node
var previous: Dictionary = {}
var travel: Dictionary = {}
var tiles: Dictionary = {}
var requested: Dictionary = {}
var failed_tiles: Dictionary = {}
var batches: Array[MeshInstance3D] = []
var total_segments := 0
var material: ShaderMaterial
var mask: Image
var texture: ImageTexture
var bounds: Rect2
var worker: Thread
var working_key := Vector2i.ZERO
var dirty := false
var clock := 0.0

func _ready() -> void:
	name="IllustrativeGroundImpressions"
	var center := Vector2(world.rover.chassis.global_position.x,world.rover.chassis.global_position.z)
	bounds=Rect2((center/TILE).floor()*TILE-Vector2.ONE*SPAN*0.5,Vector2.ONE*SPAN)
	mask=Image.create(PIXELS,PIXELS,false,Image.FORMAT_RGBA8)
	mask.fill(Color(0,NEUTRAL,0,1))
	texture=ImageTexture.create_from_image(mask)
	bind_materials()

func bind_materials() -> void:
	if texture==null or world.surface_materials.is_empty(): return
	if material==null:
		material=world.surface_materials[0].duplicate()
		material.set_shader_parameter("track_overlay",true)
	world.graph.surface_style.apply(material,world.source_appearance)
	for parameter in ["imagery","cavity_map","terrain_bounds"]:
		material.set_shader_parameter(parameter,world.surface_materials[0].get_shader_parameter(parameter))
	for base in world.surface_materials+[material,world.gravel_material]:
		base.set_shader_parameter("tracks_enabled",not world.source_appearance)
		base.set_shader_parameter("track_mask",texture)
		base.set_shader_parameter("track_bounds",Vector4(bounds.position.x,bounds.position.y,SPAN,SPAN))
	visible=not world.source_appearance

func coverage(point: Vector2) -> float:
	if not bounds.has_point(point): return 0.0
	var pixel := ((point-bounds.position)/SPAN*PIXELS).floor()
	return mask.get_pixel(clampi(int(pixel.x),0,PIXELS-1),clampi(int(pixel.y),0,PIXELS-1)).b

func _physics_process(_dt: float) -> void:
	visible=not world.source_appearance
	if not visible: previous.clear(); return
	for i in world.rover.wheels.size():
		var body: RigidBody3D = world.rover.wheels[i].body
		var point := Vector2(body.global_position.x,body.global_position.z)
		if body.contacts<=0: previous.erase(i); continue
		if not previous.has(i):
			previous[i]=point
			var forward := Vector2(world.rover.chassis.global_basis.z.x,world.rover.chassis.global_basis.z.z).normalized()
			travel[i]=point.dot(forward)
			continue
		var start: Vector2 = previous[i]
		var length := start.distance_to(point)
		if length<0.025: continue
		previous[i]=point
		if length>0.7: travel[i]=0.0; continue
		var distance: float = travel.get(i,0.0)
		var forward := Vector2(world.rover.chassis.global_basis.z.x,world.rover.chassis.global_basis.z.z).normalized()
		var direction_sign := 1.0 if (point-start).dot(forward)>=0 else -1.0
		stamp(start,point,distance,direction_sign)
		travel[i]=distance+length*direction_sign
		total_segments+=1

func stamp(start: Vector2,end: Vector2,distance: float,direction_sign: float = 1.0) -> void:
	var direction := (end-start).normalized()
	var length := start.distance_to(end)
	var area := Rect2(start,Vector2.ZERO).expand(end).grow(0.31).intersection(bounds)
	if not area.has_area(): return
	var first := ((area.position-bounds.position)/SPAN*PIXELS).floor()
	var last := ((area.end-bounds.position)/SPAN*PIXELS).ceil()
	for y in range(maxi(0,int(first.y)),mini(PIXELS,int(last.y))):
		for x in range(maxi(0,int(first.x)),mini(PIXELS,int(last.x))):
			var p := bounds.position+Vector2(x+0.5,y+0.5)*SPAN/PIXELS
			var along := (p-start).dot(direction)
			var overflow := maxf(-along,along-length)
			if overflow>0.05: continue
			var across := absf((p-start).cross(direction))
			var weight := 1.0-smoothstep(0.20,0.30,across)
			var cap := sqrt(maxf(0.0,1.0-pow(across/0.30,2)))
			var end_fade := 1.0-smoothstep(0.01,0.05,maxf(0.0,overflow)/maxf(cap,0.15))
			weight*=end_fade
			if weight<=0.001: continue
			var rut := -0.012*(1.0-smoothstep(0.14,0.22,across))
			# Phase is integrated distance, not world-coordinate projection or segment direction.
			var tread := (0.5+0.5*cos(TAU*((distance+along*direction_sign)/0.085+across*2.5)))
			rut-=0.003*tread*(1.0-smoothstep(0.13,0.19,across))
			rut+=0.003*exp(-pow((across-0.23)/0.035,2))
			rut*=end_fade
			var old := mask.get_pixel(x,y)
			var old_depth := (old.g-NEUTRAL)*0.04
			var depth := minf(old_depth,rut) if rut<0 or old_depth<0 else maxf(old_depth,rut)
			mask.set_pixel(x,y,Color(old.r,NEUTRAL+depth/0.04,maxf(old.b,weight),1))
			requested[Vector2i(floori(p.x/TILE),floori(p.y/TILE))]=true
	dirty=true

func _process(dt: float) -> void:
	if mask==null: return
	clock+=dt/maxf(Engine.time_scale,0.001)
	if worker!=null and not worker.is_alive():
		var arrays: Array = worker.wait_to_finish()
		worker=null
		if not arrays.is_empty() and tile_inside(working_key): install(working_key,arrays)
		elif arrays.is_empty():
			failed_tiles[working_key]=true
			push_warning("Cosmetic track preparation unavailable; sourced ground retained")
	if worker==null: recenter()
	# Lock only touched parent chunks at 1 m so replacement boundaries stay stable.
	var locks := {}
	for key in requested:
		var parent := parent_chunk(key)
		if not parent.is_empty(): locks[parent.id]=true
	world.detail.locked_chunks=locks
	if worker==null:
		for key in requested:
			if tiles.has(key) or failed_tiles.has(key): continue
			var parent := parent_chunk(key)
			if parent.is_empty() or int(parent.cells)!=64: continue
			if world.detail.morphs.has(parent.id) and world.detail.morphs[parent.id].is_running(): continue
			working_key=key
			var field := TerrainHeightField.new()
			field.region=world.result.region; field.service=world.service
			worker=Thread.new()
			if worker.start(build_tile.bind(key,parent,field))!=OK: worker=null
			break
	if dirty and clock>=0.1: flush(); clock=0

func parent_chunk(key: Vector2i) -> Dictionary:
	var center := Vector2(key)*TILE+Vector2.ONE*TILE*0.5
	for parent in world.detail.current.values():
		if parent.bounds.has_point(center): return parent
	return {}

func tile_inside(key: Vector2i) -> bool:
	return bounds.encloses(Rect2(Vector2(key)*TILE,Vector2.ONE*TILE))

func recenter() -> void:
	var position := Vector2(world.rover.chassis.global_position.x,world.rover.chassis.global_position.z)
	var origin := (position/TILE).floor()*TILE-Vector2.ONE*SPAN*0.5
	if origin==bounds.position: return
	var offset := Vector2i((bounds.position-origin)*PIXELS/SPAN)
	var shifted := Image.create(PIXELS,PIXELS,false,Image.FORMAT_RGBA8)
	shifted.fill(Color(0,NEUTRAL,0,1))
	shifted.blit_rect(mask,Rect2i(0,0,PIXELS,PIXELS),offset)
	mask=shifted
	bounds.position=origin
	for key in requested.keys():
		if not tile_inside(key):
			requested.erase(key)
			if tiles.has(key):
				batches.erase(tiles[key]); tiles[key].queue_free(); tiles.erase(key)
	dirty=true
	bind_materials()

func build_tile(key: Vector2i,parent: Dictionary,field: TerrainHeightField) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var origin := Vector2(key)*TILE
	var atlas: Rect2 = field.region.terrain_bounds()
	for y in range(CELLS+1):
		for x in range(CELLS+1):
			var p := origin+Vector2(x,y)*TILE/CELLS
			var uv: Vector2 = (p-parent.bounds.position)/parent.bounds.size
			var coarse := TerrainDetailMesh.grid_sample(parent.arrays,int(parent.cells),uv)
			var sample := field.sample(p.x,p.y)
			if not sample.valid: return []
			var edge := minf(minf(x,y),minf(CELLS-x,CELLS-y))*TILE/CELLS
			var blend := smoothstep(0.0,0.25,edge)
			vertices.append(Vector3(p.x,lerpf(coarse.height,sample.height,blend),p.y))
			normals.append(coarse.normal.lerp(field.normal(p.x,p.y),blend).normalized())
			uvs.append((p-atlas.position)/atlas.size)
	for y in CELLS:
		for x in CELLS:
			var a := y*(CELLS+1)+x
			indices.append_array(PackedInt32Array([a,a+1,a+CELLS+1,a+1,a+CELLS+2,a+CELLS+1]))
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uvs; arrays[Mesh.ARRAY_INDEX]=indices
	return arrays

func install(key: Vector2i,arrays: Array) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var visual := MeshInstance3D.new()
	visual.mesh=mesh; visual.material_override=material
	add_child(visual); tiles[key]=visual; batches.append(visual)
	# Activate ground replacement only after its mesh exists: no holes while loading.
	var first := Vector2i((Vector2(key)*TILE-bounds.position)*PIXELS/SPAN)
	for y in range(first.y,first.y+PIXELS/4):
		for x in range(first.x,first.x+PIXELS/4):
			var value := mask.get_pixel(x,y)
			value.r=1; mask.set_pixel(x,y,value)
	dirty=true

func flush() -> void:
	if texture!=null and dirty:
		texture.update(mask)
		dirty=false

func _exit_tree() -> void:
	if worker!=null: worker.wait_to_finish()
