class_name PlanetTileStreamer
extends Node

signal status_changed(message: String)
var rig: PlanetCameraRig
var stable_seconds := 0.0
var view_key := ""
var view_origin := Vector2.INF
var service: PlanetSurfaceService
var offline := "--planet-offline" in OS.get_cmdline_user_args()
var cache_root := "user://planetary_tiles/"
var disk_limit := 2*1024*1024*1024
var memory_limit := 512*1024*1024
var pid := -1
var active: Dictionary = {}
var queue: Array[Dictionary] = []
var generation := 0
var timeout := 0.0
var completed: Dictionary = {}
var completion_order: Array[String] = []
var cache_hits := 0
var cache_misses := 0
var jobs_cancelled := 0
var bytes_downloaded := 0
var last_latency_s := 0.0
var job_started_usec := 0
var tile_cache := MarsTileCache.new()
var prefetched_tiles := 0
var predicted_direction := Vector2.ZERO
var tile_package := MarsTilePackage.new()
var surrounding_key := ""
var surrounding_timer := 0.0
var surrounding_rectangles: Array[Rect2] = []

func request_surroundings(rectangles: Array[Rect2]) -> void:
	cancel()
	surrounding_rectangles=rectangles
	if offline:
		status_changed.emit("OFFLINE  /  Bundled surroundings available")
		return
	for bounds in rectangles:
		var key := MarsTileAddress.cache_key("imagery",bounds,1024,"mars_trek_view_v1")
		queue.append({"key":key,"kind":"imagery","bounds":[bounds.position.x,bounds.position.y,bounds.end.x,bounds.end.y],"size":1024,"generation":generation,"prefetch":false,"provider":"mars_trek"})
	status_changed.emit("LOADING SURROUNDING DETAIL")

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(cache_root)
	prune_cache()
	tile_package.load_index()

func request_cell(bounds: Rect2, size: int = 512) -> void:
	cancel()
	if offline:
		status_changed.emit("OFFLINE  /  Bundled terrain remains available")
		return
	enqueue_bounds(bounds,clampi(size,256,1024),false)
	if not offline: status_changed.emit("CHECKING PUBLISHED COVERAGE")

func enqueue_bounds(bounds: Rect2, size: int, prefetch: bool, address: Dictionary = {}) -> void:
	if bounds.size.x<=0 or bounds.size.y<=0 or bounds.position.x< -180 or bounds.end.x>180 or bounds.position.y< -90 or bounds.end.y>90: return
	for kind in ["elevation","imagery"]:
		var key := MarsTileAddress.cache_key(kind,bounds,size)
		if active.get("key","")==key: continue
		var duplicate := false
		for old in queue:
			if old.key==key: duplicate=true
		if duplicate: continue
		queue.append({"key":key,"kind":kind,"bounds":[bounds.position.x,bounds.position.y,bounds.end.x,bounds.end.y],"size":size,"generation":generation,"prefetch":prefetch,"tile":address,"provider":"usgs_stac"})

func request_view(center: Vector2, level: int, direction: Vector2 = Vector2.ZERO) -> void:
	cancel()
	var address := MarsTileAddress.at(center.x,center.y,level)
	enqueue_bounds(address.bounds,512,false,address)
	# One predicted neighbour only; foreground elevation and imagery always run first.
	if not offline and direction.length()>0.00001:
		var dx := int(signf(direction.x)) if absf(direction.x)>=absf(direction.y) else 0
		var dy := -int(signf(direction.y)) if dx==0 else 0
		var neighbour := MarsTileAddress.tile(level,int(address.x)+dx,int(address.y)+dy)
		if neighbour.x!=address.x or neighbour.y!=address.y: enqueue_bounds(neighbour.bounds,512,true,neighbour)
	status_changed.emit("PREPARING LOCAL DETAIL" if offline else "CHECKING PUBLISHED COVERAGE")

func cancel() -> void:
	generation+=1
	queue.clear()
	if pid>0 and OS.is_process_running(pid): OS.kill(pid)
	if pid>0: jobs_cancelled+=1
	pid=-1
	active.clear()

func worker_path() -> String:
	var path := ProjectSettings.globalize_path("res://planetary_map/tools/mars_terrain_worker/mars_terrain_worker.exe")
	if FileAccess.file_exists(path): return path
	# Exported games ship the worker beside the executable, outside the PCK.
	return OS.get_executable_path().get_base_dir()+"/planetary_map/tools/mars_terrain_worker/mars_terrain_worker.exe"

func start_job(job: Dictionary) -> void:
	active=job
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_root))
	job_started_usec=Time.get_ticks_usec()
	var address: Dictionary=job.get("tile",{})
	if not address.is_empty():
		var identity := {"z":address.z,"x":address.x,"y":address.y}
		var packaged := tile_package.matching(identity,job.kind)
		if not packaged.is_empty():
			var accepted := 0
			for metadata in packaged:
				var record: Dictionary=metadata.duplicate(true)
				record.path=tile_package.base+record.path
				record.validity_mask_path=tile_package.base+record.validity_mask_path
				var result := {"ok":true,"datasets":[record]}
				if not tile_cache.valid(result,true): continue
				if not job.get("prefetch",false):
					active["from_cache"]=true
					accept(result)
				accepted+=1
			if accepted>0:
				status_changed.emit("BUNDLED  /  Local detail ready")
				active.clear()
				return
	var suffix := ".height" if job.kind=="elevation" else ".png"
	job["output"] = ProjectSettings.globalize_path(cache_root+job.key+suffix)
	job["areoid"] = ProjectSettings.globalize_path(PlanetSurfaceService.ROOT+"areoid16.bin")
	job["discovery"]=service.source_adapters[0].discovery_request()
	job["catalog_cache"]=ProjectSettings.globalize_path(cache_root+"catalog/")
	# Raw assets in exported PCKs must be copied once for the GDAL child process.
	if not FileAccess.file_exists(job.areoid):
		var datum := FileAccess.open(cache_root+"areoid16.bin",FileAccess.WRITE)
		datum.store_buffer(service.areoid)
		datum.close()
		job.areoid = ProjectSettings.globalize_path(cache_root+"areoid16.bin")
	job["result"] = str(job.output).get_basename()+".json"
	tile_cache.root_path=cache_root
	if FileAccess.file_exists(job.result):
		var cached = JSON.parse_string(FileAccess.get_file_as_string(job.result))
		if cached is Dictionary and cached.get("ok",false) and cached_files_exist(cached):
			cache_hits+=1
			active["from_cache"]=true
			last_latency_s=float(Time.get_ticks_usec()-job_started_usec)/1000000.0 if job_started_usec>0 else 0.0
			tile_cache.touch(job.result,cached)
			if not job.get("prefetch",false): accept(cached)
			active.clear()
			return
		# Invalid groups are retried instead of repeatedly reused.
		if not offline: tile_cache.discard(job.result)
	if offline:
		active.clear()
		status_changed.emit("OFFLINE  /  Bundled and valid cached terrain retained")
		return
	var executable := worker_path()
	if not FileAccess.file_exists(executable):
		status_changed.emit("Streaming unavailable; using bundled data")
		active.clear()
		queue.clear()
		return
	cache_misses+=1
	var request_path := cache_root+"request_"+str(generation)+".json"
	var request := FileAccess.open(request_path,FileAccess.WRITE)
	request.store_string(JSON.stringify(job))
	request.close()
	# Remove a previous failure response so it cannot be mistaken for this job.
	if FileAccess.file_exists(job.result): DirAccess.remove_absolute(job.result)
	pid=OS.create_process(executable,PackedStringArray(["--request",ProjectSettings.globalize_path(request_path)]),false)
	timeout=0
	job_started_usec=Time.get_ticks_usec()
	if pid<0:
		active.clear()
		status_changed.emit("Streaming worker could not start; bundled data retained")

func cached_files_exist(result: Dictionary) -> bool:
	return tile_cache.valid(result,offline)

func accept(result: Dictionary) -> void:
	result["id"] = active.key
	result["prepared_spacing_m"] = result.get("prepared_spacing_m",1000)
	if result.get("ok",false):
		for metadata in result.get("datasets",[]):
			var stream_path:=str(metadata.get("path",""))
			if not active.get("from_cache",false) and FileAccess.file_exists(stream_path):
				var handle := FileAccess.open(stream_path,FileAccess.READ)
				if handle!=null: bytes_downloaded+=handle.get_length()
		last_latency_s=float(Time.get_ticks_usec()-job_started_usec)/1000000.0 if job_started_usec>0 else 0.0
		var records: Array = result.get("datasets",[result])
		var count := 0
		for metadata in records:
			metadata["id"]=active.key+"_"+str(count)
			metadata["accepted_usec"]=Time.get_ticks_usec()
			var data := service.add_dataset(metadata)
			if data != null:
				completed[data.id]=true
				completion_order.erase(data.id)
				completion_order.append(data.id)
				count+=1
		for item in result.get("published_items",[]):
			var known := false
			for old in service.source_catalog:
				if old.id==item.id: known=true; break
			if not known: service.source_catalog.append(item)
			service.source_adapters[0].register_record(item)
			if not known: service.coverage_index.records.append(item)
		enforce_memory()
		var origin := "SAVED" if active.get("from_cache",false) else "DOWNLOADED"
		if active.get("provider","")=="mars_trek" and count>0:
			var partial := float(records[0].get("valid_fraction",0))<0.99
			status_changed.emit("SURROUNDINGS %s  /  CTX visible; preliminary, uncontrolled" % ("PARTIAL" if partial else "READY"))
		else:
			status_changed.emit("%s  /  %d local %s sources available" % [origin,count,active.kind] if count>0 else "Detail failed validation; bundled data retained")
	else:
		status_changed.emit("No usable "+str(active.kind)+" tile; existing data retained")
		push_warning("Optional terrain stream: "+str(result.get("error","unknown failure")))

func _process(dt: float) -> void:
	surrounding_timer+=dt
	if rig!=null and not rig.locked:
		var center := Vector2(rad_to_deg(rig.yaw),rad_to_deg(rig.pitch))
		if not active.get("tile",{}).is_empty() and not view_key.is_empty():
			var current_tile := MarsTileAddress.at(center.x,center.y,int(active.tile.z))
			if "%d/%d/%d" % [current_tile.z,current_tile.x,current_tile.y]!=view_key:
				cancel()
				view_key=""
		if center.distance_to(view_origin)>0.02 or rig.focusing:
			if is_finite(view_origin.x): predicted_direction=Vector2(wrapf(center.x-view_origin.x,-180,180),center.y-view_origin.y)
			stable_seconds=0
			view_origin=center
		else: stable_seconds+=dt
		if stable_seconds>0.6 and rig.distance/service.radius<1.12 and surrounding_timer>0.5:
			surrounding_timer=0
			var rectangles := MarsViewFootprint.bounds(rig.camera,service,center.x)
			var next_key := MarsViewFootprint.key(rectangles)
			if not rectangles.is_empty() and next_key!=surrounding_key:
				surrounding_key=next_key
				request_surroundings(rectangles)
		if stable_seconds>1.5 and rig.distance/service.radius<1.06 and pid<0 and queue.is_empty():
			var altitude := maxf((rig.distance/service.radius-1.0)*service.physical_radius_m,85.0)
			var spacing := 2.0*altitude*tan(deg_to_rad(rig.camera.fov)*0.5)/maxf(rig.camera.get_viewport().get_visible_rect().size.y,1)
			var level := clampi(int(ceil(log(PI*service.physical_radius_m/512.0/spacing)/log(2.0))),9,14)
			var address := MarsTileAddress.at(center.x,center.y,level)
			var key := "%d/%d/%d" % [level,address.x,address.y]
			if key!=view_key:
				view_key=key
				var terrain := service.sample(center.y,center.x)
				var imagery := false
				for data in service.datasets:
					if data.kind=="imagery" and data.imagery_valid(center.y,center.x): imagery=true
				var packaged := tile_package.matching({"z":level,"x":address.x,"y":address.y},"elevation")
				if str(terrain.source).begins_with("MOLA") or not imagery or not packaged.is_empty():
					# Keep center elevation/local orthophotos behind visible-area imagery.
					enqueue_bounds(address.bounds,512,false,address)
	if pid>0:
		timeout+=dt
		if timeout>120:
			OS.kill(pid)
			pid=-1
			active.clear()
			status_changed.emit("Download timed out; bundled data retained")
		elif not OS.is_process_running(pid):
			pid=-1
			var result = JSON.parse_string(FileAccess.get_file_as_string(active.result)) if FileAccess.file_exists(active.result) else null
			if result is Dictionary and active.generation==generation:
				if tile_cache.valid(result):
					result["cached_at"]=Time.get_unix_time_from_system()
					tile_cache.touch(active.result,result)
					if active.get("prefetch",false): prefetched_tiles+=1
					else: accept(result)
				else: status_changed.emit("No valid tile; bundled data retained")
			else: status_changed.emit("Download interrupted; bundled data retained")
			active.clear()
			prune_cache()
	if pid<0 and active.is_empty() and not queue.is_empty(): start_job(queue.pop_front())

func enforce_memory() -> void:
	var usage := service.areoid.size()+service.overview.size()+96*256*256*2
	for data in service.datasets:
		usage+=data.heights.size()*4
		usage+=data.validity_bits.size()
		if data.image!=null: usage+=data.image.get_data_size()*2
	while not completion_order.is_empty() and (usage>memory_limit or completion_order.size()>8):
		var found := false
		var oldest: String = completion_order.pop_front()
		for data in service.datasets:
			if data.id!=oldest: continue
			usage-=data.heights.size()*4
			usage-=data.validity_bits.size()
			if data.image!=null: usage-=data.image.get_data_size()*2
			service.mutex.lock()
			service.datasets.erase(data)
			service.mutex.unlock()
			completed.erase(data.id)
			found=true
			break
		if not found: break
	service.data_changed.emit()

func prune_cache() -> void:
	tile_cache.root_path=cache_root
	var protected_paths: Array[String] = []
	if not active.is_empty():
		for field in ["output","result"]:
			if active.has(field): protected_paths.append(str(active[field]))
	tile_cache.prune(disk_limit,protected_paths)

func _exit_tree() -> void:
	cancel()
