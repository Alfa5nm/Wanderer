class_name TerrainPatchBuilder
extends Node

signal completed(result: TerrainPatchResult)
signal failed(message: String)
var service: PlanetSurfaceService
var evaluator := TerrainGraphEvaluator.new()
var worker: Thread
var cancelled := false
var busy := false

func start(graph: TerrainGenerationGraph,region: TerrainMissionRegion) -> bool:
	if busy or service==null or not region.valid(): return false
	if service.overview.size()!=1440*720*2:
		failed.emit("Required numeric MOLA core is missing; restore terrain assets and retry.")
		return false
	var images: Array = []
	var elevation_versions: Array = [FileAccess.get_modified_time(PlanetSurfaceService.ROOT+"manifest.json"),PlanetSurfaceService.checksum(service.overview)]
	var image_versions: Array = [FileAccess.get_modified_time("res://planetary_map/assets/mars_viking_4k.jpg")]
	var footprint := region.terrain_bounds().grow(1536)
	var low := Vector2(INF,INF)
	var high := Vector2(-INF,-INF)
	for corner in [footprint.position,footprint.end,Vector2(footprint.end.x,footprint.position.y),Vector2(footprint.position.x,footprint.end.y)]:
		var geo := region.geographic(corner.x,corner.y)
		low=low.min(Vector2(geo.y,geo.x)); high=high.max(Vector2(geo.y,geo.x))
	var conservative := absf(region.latitude)>89 or high.x-low.x>180
	var geographic := Rect2(low,high-low).grow(0.00001)
	for data in service.datasets:
		var version = [data.id,data.product_id,data.width,data.height,data.metadata.get("accepted_usec",0),data.metadata.get("sha256",""),data.metadata.get("validity_mask_sha256",""),str(data.bounds)]
		if data.kind=="imagery" and data.image!=null and (conservative or data.bounds.intersects(geographic)): images.append(data); image_versions.append(version)
		if data.kind=="elevation": elevation_versions.append(version)
	images.sort_custom(func(a: PlanetDataset,b: PlanetDataset): return a.prepared_spacing_m>b.prepared_spacing_m)
	var context = {"region":region.duplicate(),"service":service,"images":images,"global_image":null,"elevation_version":JSON.stringify(elevation_versions),"imagery_version":JSON.stringify(image_versions)}
	# Immutable descriptors/images for the worker; no rendering or physics calls here.
	cancelled=false; busy=true
	worker=Thread.new()
	var error = worker.start(evaluator.evaluate.bind(graph.duplicate(true),context))
	if error!=OK:
		worker=null; busy=false
		failed.emit("Terrain preparation could not start")
		return false
	return true

func cancel() -> void:
	cancelled=true

func _process(_dt: float) -> void:
	if worker==null or worker.is_alive(): return
	var result: TerrainPatchResult = worker.wait_to_finish()
	worker=null; busy=false
	if cancelled: return
	if result==null or not result.valid: failed.emit("Terrain preparation failed: "+("; ".join(result.warnings) if result!=null else "worker error"))
	else: completed.emit(result)

func _exit_tree() -> void:
	if worker!=null: worker.wait_to_finish(); worker=null
