extends SceneTree

class MissingWorker:
	extends PlanetTileStreamer
	func worker_path() -> String:
		return "res://tests/intentionally_missing_worker.exe"

var checks: Dictionary = {}
func check(id: String, value: bool) -> void:
	checks[id]=value
	if not value: push_error("FAIL: "+id)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var service := PlanetSurfaceService.new()
	root.add_child(service)
	var core_ids: Array[String]=[]
	for data in service.datasets: core_ids.append(data.id)
	var stream := PlanetTileStreamer.new()
	stream.service=service
	stream.cache_root="user://terrain_stream_test/"
	root.add_child(stream)
	var response = JSON.parse_string(FileAccess.get_file_as_string("res://.tools/stream_test.json"))
	check("packaged_remote_read",response is Dictionary and response.get("ok",false) and response.datasets.size()==2)
	var fine := false
	for data in response.datasets: fine=fine or data.product_id=="DTEEC_018854_1755_018920_1755_U01"
	check("remote_valid_hirise_found",fine)
	FileAccess.open(stream.cache_root+"warm.json",FileAccess.WRITE).store_string(JSON.stringify(response))
	stream.start_job({"key":"warm","kind":"elevation","generation":stream.generation})
	check("warm_cache_without_worker",stream.pid<0 and stream.completed.size()==2 and stream.active.is_empty())
	var metadata: Dictionary = response.datasets[0].duplicate(true)
	metadata.sha256="invalid-checksum"
	metadata.id="corrupt-fixture"
	check("corrupt_tile_rejected",service.add_dataset(metadata)==null)
	var missing: Dictionary = response.duplicate(true)
	missing.datasets[0].path="res://tests/intentionally_missing_tile.height"
	check("missing_cache_asset_detected",not stream.cached_files_exist(missing))
	var fallback := service.sample(-4.5895,137.4417)
	check("fallback_survives_corruption",fallback.valid and fallback.source.begins_with("HiRISE"))
	stream.memory_limit=1
	stream.enforce_memory()
	check("stream_eviction_preserves_core",stream.completed.is_empty() and service.datasets.size()==core_ids.size() and service.datasets.all(func(data): return data.id in core_ids))
	var failed := MissingWorker.new()
	failed.service=service
	failed.cache_root=stream.cache_root
	root.add_child(failed)
	var status: Array[String] = []
	failed.status_changed.connect(func(message: String): status.append(message))
	failed.start_job({"key":"missing-worker","kind":"elevation","generation":failed.generation})
	check("worker_failure_keeps_core",failed.pid<0 and not status.is_empty() and service.sample(-4.5895,137.4417).valid)
	stream.offline=false
	stream.request_cell(Rect2(137.435,-4.595,0.013,0.013))
	await create_timer(0.1).timeout
	var previous_pid := stream.pid
	var previous_generation := stream.generation
	stream.cancel()
	await create_timer(0.1).timeout
	check("interrupted_worker_cancelled",previous_pid>0 and not OS.is_process_running(previous_pid) and stream.generation>previous_generation and stream.queue.is_empty())
	stream.offline=true
	stream.request_cell(Rect2(137.435,-4.595,0.013,0.013))
	check("offline_preserves_bundled",stream.pid<0 and service.datasets.size()==core_ids.size() and service.datasets.all(func(data): return data.id in core_ids))
	# A separate cache directory makes pruning safe and repeatable.
	stream.cache_root="user://terrain_cache_limit_test/"
	DirAccess.make_dir_recursive_absolute(stream.cache_root)
	var bytes := PackedByteArray()
	bytes.resize(8192)
	for name in ["one.bin","two.bin","three.bin"]:
		FileAccess.open(stream.cache_root+name,FileAccess.WRITE).store_buffer(bytes)
	stream.disk_limit=10000
	stream.prune_cache()
	check("disk_cache_cap",DirAccess.get_files_at(stream.cache_root).size()==1)
	var decoded := service.areoid.size()+service.overview.size()+96*256*256*2
	for data in service.datasets:
		decoded+=data.heights.size()*4+data.validity_bits.size()
		if data.image!=null: decoded+=data.image.get_data_size()*2
	check("core_decoded_budget",decoded<=512*1024*1024)
	checks["decoded_core_mib"]=float(decoded)/1048576
	FileAccess.open("res://evidence/terrain_streaming_checks.json",FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
	print(JSON.stringify(checks))
	var failed_check := false
	for value in checks.values():
		if value is bool and not value: failed_check=true
	stream.queue_free(); failed.queue_free(); service.queue_free()
	await process_frame
	quit(1 if failed_check else 0)
