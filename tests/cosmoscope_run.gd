extends SceneTree

var checks := {}
func check(id: String, value: bool) -> void:
	checks[id]=value
	if not value: push_error("FAIL: "+id)

func _initialize() -> void:
	call_deferred("run")

func fixture(cache: MarsTileCache, key: String, age: float) -> Dictionary:
	var path := cache.root_path+key+".height"
	var bytes := PackedFloat32Array([1.0,2.0,3.0,4.0]).to_byte_array()
	FileAccess.open(path,FileAccess.WRITE).store_buffer(bytes.compress(FileAccess.COMPRESSION_DEFLATE))
	var mask := PackedByteArray([15]).compress(FileAccess.COMPRESSION_DEFLATE)
	FileAccess.open(path+".validity.z",FileAccess.WRITE).store_buffer(mask)
	var record := {"path":path,"kind":"elevation","width":2,"height":2,"sha256":PlanetSurfaceService.checksum(bytes),"validity_mask_path":path+".validity.z","validity_mask_sha256":PlanetSurfaceService.checksum(mask),"validity_mask_encoding":"bit-lsb"}
	var result := {"ok":true,"datasets":[record],"cached_at":Time.get_unix_time_from_system()-age,"last_access":Time.get_unix_time_from_system()-age}
	FileAccess.open(cache.root_path+key+".json",FileAccess.WRITE).store_string(JSON.stringify(result))
	return result

func run() -> void:
	var address := MarsTileAddress.at(137.4417,-4.5895,12)
	check("tile_contains_destination",address.bounds.has_point(Vector2(137.4417,-4.5895)))
	check("longitude_seam_wrap",MarsTileAddress.at(-180,0,12)==MarsTileAddress.at(180,0,12))
	check("north_pole_bounded",MarsTileAddress.at(50,90,12).bounds.end.y==90)
	check("south_pole_bounded",MarsTileAddress.at(50,-90,12).bounds.position.y== -90)
	var parent := MarsTileAddress.tile(11,int(address.x)/2,int(address.y)/2)
	check("parent_contains_child",parent.bounds.encloses(address.bounds))
	check("shared_tile_edge",MarsTileAddress.tile(12,int(address.x)+1,int(address.y)).bounds.position.x==address.bounds.end.x)
	var key := MarsTileAddress.cache_key("elevation",address.bounds,512)
	check("deterministic_hashed_key",key.length()==64 and key==MarsTileAddress.cache_key("elevation",address.bounds,512))
	check("independent_imagery_namespace",key!=MarsTileAddress.cache_key("imagery",address.bounds,512))
	check("provider_namespace",key!=MarsTileAddress.cache_key("elevation",address.bounds,512,"other"))
	var cache := MarsTileCache.new()
	cache.root_path="user://cosmoscope_cache_test/"
	DirAccess.make_dir_recursive_absolute(cache.root_path)
	cache.prune(0)
	var valid := fixture(cache,"valid",0)
	check("valid_group_reusable",cache.valid(valid))
	var expired := fixture(cache,"expired",cache.ttl_seconds+1)
	check("ttl_rejects_stale",not cache.valid(expired))
	check("offline_allows_valid_stale",cache.valid(expired,true))
	var broken := valid.duplicate(true)
	broken.datasets[0].sha256="bad"
	check("warm_cache_checks_height_hash",not cache.valid(broken))
	broken=valid.duplicate(true)
	broken.datasets[0].validity_mask_sha256="bad"
	check("warm_cache_checks_mask_hash",not cache.valid(broken))
	cache.max_entry_bytes=1
	check("entry_size_limit",not cache.valid(valid))
	cache.max_entry_bytes=64*1024*1024
	cache.prune(1,[str(valid.datasets[0].path)])
	check("active_group_retained",FileAccess.file_exists(cache.root_path+"valid.json") and FileAccess.file_exists(valid.datasets[0].validity_mask_path))
	check("eviction_removes_whole_group",not FileAccess.file_exists(cache.root_path+"expired.json") and not FileAccess.file_exists(expired.datasets[0].path) and not FileAccess.file_exists(expired.datasets[0].validity_mask_path))
	check("cache_path_containment",not cache.owns("res://project.godot") and not cache.owns(cache.root_path+"../external.bin"))
	cache.prune(0)
	var adapter := MarsUSGSStacAdapter.new()
	adapter.register_record({"id":"test","bbox":[137.4,-4.7,137.5,-4.5],"assets":{"dtm":{}}})
	adapter.register_record({"id":"test","bbox":[137.4,-4.7,137.5,-4.5],"assets":{"dtm":{}}})
	check("adapter_index_filters_kind",adapter.find_intersecting(address.bounds,"elevation").size()==1 and adapter.find_intersecting(address.bounds,"imagery").is_empty())
	check("adapter_worker_contract",adapter.discovery_request().collections.size()==2 and adapter.published_records.size()==1)
	var stream := PlanetTileStreamer.new()
	stream.offline=false
	stream.request_view(Vector2(137.4417,-4.5895),12,Vector2.RIGHT)
	check("bounded_prediction_queue",stream.queue.size()==4 and not stream.queue[0].prefetch and not stream.queue[1].prefetch and stream.queue[2].prefetch)
	var neighbour: Dictionary=stream.queue[2].tile
	check("prediction_matches_heading",neighbour.x==address.x+1 and neighbour.y==address.y)
	stream.request_cell(Rect2(137.43,-4.60,0.02,0.02))
	check("destination_preempts_prediction",stream.queue.size()==2 and not stream.queue[0].prefetch)
	stream.cancel()
	check("cancel_invalidates_generation",stream.queue.is_empty() and stream.generation==3)
	stream.free()
	var service := PlanetSurfaceService.new()
	root.add_child(service)
	check("pds_index_has_numeric_global_products",not service.source_adapters[1].find_intersecting(Rect2(137,-5,1,1),"elevation").is_empty())
	check("trek_index_has_sourced_imagery",not service.source_adapters[2].find_intersecting(Rect2(137,-5,1,1),"imagery").is_empty())
	var package := MarsTilePackage.new()
	package.load_index()
	var target := MarsTileAddress.at(137.4417,-4.5895,14)
	var tile_id := {"z":target.z,"x":target.x,"y":target.y}
	var heights := package.matching(tile_id,"elevation")
	check("offline_pyramid_has_independent_assets",heights.size()==1 and package.matching(tile_id,"imagery").size()==1)
	if heights.is_empty(): quit(1); return
	var parent_id := {"z":13,"x":int(target.x)/2,"y":int(target.y)/2}
	check("prepared_parent_available",package.matching(parent_id,"elevation").size()==1)
	var source_value: float = service.sample(-4.5895,137.4417).offset_m
	var data := service.add_dataset(heights[0].duplicate(true),package.base)
	check("pyramid_keeps_radial_datum",data!=null and is_finite(data.elevation(-4.5895,137.4417)) and absf(data.elevation(-4.5895,137.4417)-source_value)<1.0)
	var packaged_stream := PlanetTileStreamer.new()
	packaged_stream.service=service
	packaged_stream.offline=true
	packaged_stream.cache_root="user://cosmoscope_package_test/"
	root.add_child(packaged_stream)
	packaged_stream.start_job({"key":"package-proof","kind":"elevation","generation":packaged_stream.generation,"tile":target})
	check("bundled_pyramid_loads_without_worker",packaged_stream.pid<0 and packaged_stream.completed.size()==1 and packaged_stream.active.is_empty())
	packaged_stream.start_job({"key":"no-offline-worker","kind":"imagery","generation":packaged_stream.generation})
	check("offline_miss_never_starts_worker",packaged_stream.pid<0 and packaged_stream.active.is_empty())
	packaged_stream.queue_free()
	service.queue_free()
	await process_frame
	FileAccess.open("res://evidence/cosmoscope_checks.json",FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
	print(JSON.stringify(checks))
	quit(1 if checks.values().has(false) else 0)
