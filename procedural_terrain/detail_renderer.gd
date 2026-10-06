class_name TerrainDetailRenderer
extends Node

const CELLS := [64,32,16,8,4]
var patch: TerrainPatchResult
var bases: Dictionary = {}
var current: Dictionary = {}
var visuals: Dictionary = {}
var estimates: Dictionary = {}
var levels: Dictionary = {}
var worker: Thread
var uploads: Array = []
var morphs: Dictionary = {}
var artifacts := TerrainArtifactCache.new()
var camera: Camera3D
var quality := 1
var suspended := false
var locked_chunks: Dictionary = {}
var generation := 0
var elapsed := 0.0
var dynamic_request := false
var request_position := Vector3.ZERO
var request_forward := Vector3.FORWARD
var metrics := {"uploads":0,"max_upload_ms":0.0,"last_worker_ms":0.0,"disk_hits":0,"max_queue":0,"cancelled_requests":0}

func configure(value: TerrainPatchResult,root: Node3D) -> void:
	generation+=1
	if worker!=null: worker.wait_to_finish(); worker=null
	for tween in morphs.values(): if tween.is_valid(): tween.kill()
	patch=value; bases={}; current={}; visuals={}; estimates={}; levels={}; uploads=[]; morphs={}
	for body in root.get_children():
		if not body.has_meta("chunk") or body.get_meta("scenery",false): continue
		var chunk: Dictionary = body.get_meta("chunk").duplicate()
		chunk["cells"]=roundi(sqrt(chunk.arrays[Mesh.ARRAY_VERTEX].size()))-1
		bases[chunk.id]=chunk; current[chunk.id]=chunk
		visuals[chunk.id]=body.get_child(0)
		levels[chunk.id]=clampi(roundi(log(64.0/chunk.cells)/log(2.0)),0,4)
	elapsed=0.4

func set_quality(value: int) -> void:
	quality=clampi(value,0,2)
	generation+=1; uploads=[]; elapsed=0.4

func _process(dt: float) -> void:
	if patch==null: return
	if worker!=null and dynamic_request and camera!=null and (camera.global_position.distance_to(request_position)>32 or (-camera.global_basis.z).dot(request_forward)<0.75):
		generation+=1; uploads=[]; dynamic_request=false
		metrics.cancelled_requests+=1
	if worker!=null and not worker.is_alive():
		var output: Dictionary = worker.wait_to_finish()
		worker=null
		metrics.last_worker_ms=output.get("worker_ms",0.0)
		metrics.disk_hits+=output.get("disk_hits",0)
		if int(output.get("generation",-1))==generation and not suspended:
			if output.has("estimates"): estimates=output.estimates
			uploads=output.get("chunks",[])
			metrics.max_queue=maxi(metrics.max_queue,uploads.size())
	if suspended: return
	var began: int = Time.get_ticks_usec()
	var installed := 0
	while not uploads.is_empty() and installed<2:
		if installed>0 and Time.get_ticks_usec()-began>=2000: break
		install(uploads.pop_front())
		installed+=1
	if installed>0: metrics.max_upload_ms=maxf(metrics.max_upload_ms,float(Time.get_ticks_usec()-began)/1000)
	elapsed+=dt
	if worker!=null or not uploads.is_empty() or camera==null or elapsed<0.35: return
	elapsed=0
	if estimates.is_empty():
		launch({"estimate":true,"generation":generation,"bases":bases.duplicate(),"source_hash":patch.hashes.get("height",""),"geometry_hash":patch.hashes.get("geometry","")})
		return
	var desired: Dictionary = choose_levels(camera)
	var jobs: Array = []
	for id in desired:
		if desired[id]==levels[id]: continue
		if morphs.has(id) and morphs[id].is_running(): continue
		jobs.append({"base":bases[id],"old":current[id],"level":desired[id],"distance":camera.global_position.distance_to(Vector3(bases[id].bounds.get_center().x,0,bases[id].bounds.get_center().y))})
	for job in jobs:
		var bounds: Rect2 = job.base.bounds
		var visible := false
		for point in [bounds.get_center(),bounds.position,bounds.end,Vector2(bounds.position.x,bounds.end.y),Vector2(bounds.end.x,bounds.position.y)]:
			visible=visible or camera.is_position_in_frustum(Vector3(point.x,job.base.arrays[Mesh.ARRAY_VERTEX][0].y,point.y))
		job["visible"]=visible
	jobs.sort_custom(func(a,b): return a.distance<b.distance if a.visible==b.visible else a.visible)
	if not jobs.is_empty():
		# Two numeric chunks per request bound stale work and transient decoded memory.
		jobs.resize(mini(jobs.size(),2))
		launch({"jobs":jobs,"generation":generation,"source_hash":patch.hashes.get("height",""),"geometry_hash":patch.hashes.get("geometry","")})

func choose_levels(view: Camera3D) -> Dictionary:
	var output: Dictionary = {}
	var viewport_height: float = view.get_viewport().get_visible_rect().size.y
	var focal: float = viewport_height/(2*tan(deg_to_rad(view.fov)*0.5))
	var target: float = [3.0,2.0,1.0][quality]
	for id in bases:
		var base: Dictionary = bases[id]
		var center: Vector2 = base.bounds.get_center()
		var position := Vector3(center.x,base.arrays[Mesh.ARRAY_VERTEX][base.arrays[Mesh.ARRAY_VERTEX].size()/2].y,center.y)
		var distance: float = maxf(1.0,view.global_position.distance_to(position)-base.bounds.size.length()*0.5)
		var projected: float = viewport_height/maxf(view.size,0.1) if view.projection==Camera3D.PROJECTION_ORTHOGONAL else focal/distance
		var old: int = levels[id]
		var selected: int = old
		# Hysteresis surrounds the 2 px balanced target: refine >2.4; coarsen <1.6.
		while selected>0 and float(estimates[id][selected])*projected>target*1.2: selected-=1
		while selected<4 and float(estimates[id][selected+1])*projected<target*0.8: selected+=1
		output[id]=selected
		if locked_chunks.has(id): output[id]=0
	# Bound neighboring interior levels to one step; shared edge anchors remain invariant.
	for pass_index in 4:
		for id in output:
			for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				if output.has(id+offset): output[id]=mini(output[id],int(output[id+offset])+1)
	return output

func launch(request: Dictionary) -> void:
	var field := TerrainHeightField.new()
	field.service=patch.field.service; field.region=patch.region
	dynamic_request=request.has("jobs")
	if camera!=null:
		request_position=camera.global_position; request_forward=-camera.global_basis.z
	worker=Thread.new()
	if worker.start(prepare.bind(request,field))!=OK: worker=null

func prepare(request: Dictionary,field: TerrainHeightField) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var output := {"generation":request.generation,"disk_hits":0}
	if request.get("estimate",false):
		var key: String = JSON.stringify(["detail-error-4",request.source_hash,request.geometry_hash]).sha256_text()
		var cached = artifacts.read(key)
		if cached is Dictionary and cached.has("estimates"):
			output["estimates"]=cached.estimates; output.disk_hits+=1
		else:
			var result: Dictionary = {}
			for id in request.bases:
				result[id]=TerrainDetailMesh.errors(field,request.bases[id])
				if field.cache.size()>40000: field.cache.clear()
			output["estimates"]=result
			artifacts.write(key,{"estimates":result})
	else:
		var chunks: Array = []
		for job in request.jobs:
			var cells: int = CELLS[int(job.level)]
			var key: String = JSON.stringify(["detail-mesh-4",request.source_hash,request.geometry_hash,str(job.base.id),cells]).sha256_text()
			var saved = artifacts.read(key)
			var chunk: Dictionary = {}
			if saved is Array and not saved.is_empty(): chunk=saved[0]; output.disk_hits+=1
			else:
				chunk=TerrainDetailMesh.build(field,job.base,cells)
				if not chunk.is_empty(): artifacts.write(key,[chunk])
			if chunk.is_empty(): continue # Preserve the parent visual on invalid data.
			chunk=chunk.duplicate()
			chunk["previous"]=TerrainDetailMesh.previous_shape(chunk,job.old)
			chunk["level"]=job.level
			chunks.append(chunk)
		output["chunks"]=chunks
	output["worker_ms"]=float(Time.get_ticks_usec()-started)/1000
	return output

func install(chunk: Dictionary) -> void:
	var id: Vector2i = chunk.id
	if not visuals.has(id) or not is_instance_valid(visuals[id]): return
	var visual: MeshInstance3D = visuals[id]
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode=Mesh.BLEND_SHAPE_MODE_NORMALIZED
	mesh.add_blend_shape("previous")
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,chunk.arrays,[chunk.previous])
	visual.mesh=mesh
	visual.set_blend_shape_value(0,1.0)
	var tween := create_tween()
	tween.tween_method(morph_weight.bind(visual),1.0,0.0,0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	morphs[id]=tween
	current[id]=chunk
	levels[id]=chunk.level
	metrics.uploads+=1

func morph_weight(weight: float,visual: MeshInstance3D) -> void:
	if is_instance_valid(visual): visual.set_blend_shape_value(0,weight)

func _exit_tree() -> void:
	if worker!=null: worker.wait_to_finish(); worker=null
