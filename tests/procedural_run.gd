extends SceneTree

var checks = {}
var notes := {}
var last_result: TerrainPatchResult
var failed_message := ""

func _initialize() -> void: call_deferred("run")

func build(builder: TerrainPatchBuilder,graph: TerrainGenerationGraph,region: TerrainMissionRegion) -> TerrainPatchResult:
	last_result=null; failed_message=""
	if not builder.start(graph,region): return null
	var deadline = Time.get_ticks_msec()+60000
	while builder.busy and Time.get_ticks_msec()<deadline: await process_frame
	return last_result

func run() -> void:
	var service = PlanetSurfaceService.new()
	root.add_child(service)
	var builder = TerrainPatchBuilder.new()
	builder.evaluator.artifacts.root_path="user://procedural_verification/"
	DirAccess.make_dir_recursive_absolute(builder.evaluator.artifacts.root_path)
	for name in DirAccess.get_files_at(builder.evaluator.artifacts.root_path):
		if name.begins_with("patch_"): DirAccess.remove_absolute(builder.evaluator.artifacts.root_path+name)
	builder.service=service
	root.add_child(builder)
	builder.completed.connect(func(value): last_result=value)
	builder.failed.connect(func(message): failed_message=message)
	var region = TerrainMissionRegion.new()
	region.origin_radius_m=float(service.sample(region.latitude,region.longitude).radial_m)
	var roundtrip = true
	for lat in [-90.0,-4.5895,0.0,89.999,90.0]:
		for lon in [-180.0,137.4417,179.999]:
			var reference = TerrainMissionRegion.new()
			reference.latitude=lat; reference.longitude=lon
			for point in [Vector2(0,0),Vector2(100,50),Vector2(-100,-50)]:
				var ll = reference.geographic(point.x,point.y)
				var local = reference.local_from_geographic(ll.x,ll.y)
				roundtrip=roundtrip and local.is_finite() and local.distance_to(point)<1.0
	checks["local_metres_poles_and_longitude_seam"]=roundtrip
	var graph = TerrainGenerationGraph.standard()
	var result = await build(builder,graph,region)
	checks["bradbury_generates"]=result!=null and result.valid
	if result==null:
		print(failed_message); quit(1); return
	checks["bradbury_numeric_hirise"]=str(result.field.sample(0,0).source).begins_with("HiRISE")
	checks["height_matches_source"]=absf(result.field.sample(0,0).height)<0.01
	var edges = {}
	var seams = true
	var collisions = true
	for chunk in result.chunks:
		var vertices: PackedVector3Array = chunk.arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = chunk.arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			var vertex = vertices[i]+chunk.origin
			var key = Vector2(vertex.x,vertex.z)
			if edges.has(key): seams=seams and edges[key].point.distance_to(vertex)<0.00001 and edges[key].normal.distance_to(normals[i])<0.00001
			else: edges[key]={"point":vertex,"normal":normals[i]}
		var indices: PackedInt32Array = chunk.arrays[Mesh.ARRAY_INDEX]
		if chunk.get("scenery",false): collisions=collisions and chunk.faces.is_empty()
		else:
			for i in indices.size(): collisions=collisions and chunk.faces[i]==vertices[indices[i]]
	checks["shared_chunk_edges_and_normals"]=seams
	checks["collision_exactly_matches_mesh"]=collisions
	checks["seeded_rocks_repeatable"]=result.rocks==builder.evaluator.scatter(result.field,graph.node("rocks").parameters)
	notes["cold_default_ms"]=result.build_ms
	var expected_sources: Dictionary = result.sources.duplicate()
	var saved_evaluator = builder.evaluator
	builder.evaluator=TerrainGraphEvaluator.new()
	builder.evaluator.artifacts.root_path=saved_evaluator.artifacts.root_path
	result=await build(builder,graph,region)
	checks["fresh_evaluator_disk_cache"]=result!=null and result.disk_hits.has("imagery") and result.disk_hits.has("collision") and result.sources==expected_sources
	notes["warm_default_ms"]=result.build_ms
	var bad_key := "corruption_fixture"
	var bad = FileAccess.open(builder.evaluator.artifacts.path(bad_key),FileAccess.WRITE)
	bad.store_buffer(PackedByteArray([0,1,2,3])); bad.close()
	checks["corrupt_cache_rejected"]=builder.evaluator.artifacts.read(bad_key)==null
	DirAccess.remove_absolute(builder.evaluator.artifacts.path(bad_key))
	checks["cavity_disk_reuse"]=result.cavity_image!=null and result.disk_hits.has("shading")
	var base: Dictionary = result.chunks[0].duplicate()
	base["cells"]=roundi(sqrt(base.arrays[Mesh.ARRAY_VERTEX].size()))-1
	var fine: Dictionary = TerrainDetailMesh.build(result.field,base,64)
	var coarse: Dictionary = TerrainDetailMesh.build(result.field,base,4)
	var conserved := true
	var stitched := true
	var area := 0.0
	for v in fine.arrays[Mesh.ARRAY_VERTEX]:
		var p: Vector2 = Vector2(v.x+base.origin.x,v.z+base.origin.z)
		var uv: Vector2 = (p-base.bounds.position)/base.bounds.size
		if uv.x>0 and uv.y>0 and uv.x<1 and uv.y<1:
			conserved=conserved and absf(v.y-result.field.sample(p.x,p.y).height)<0.0001
		else:
			stitched=stitched and absf(v.y-TerrainDetailMesh.grid_sample(base.arrays,base.cells,uv).height)<0.0001
	var ci: PackedInt32Array = coarse.arrays[Mesh.ARRAY_INDEX]
	var cv: PackedVector3Array = coarse.arrays[Mesh.ARRAY_VERTEX]
	for i in range(0,ci.size(),3):
		var a: Vector3 = cv[ci[i]]; var b: Vector3 = cv[ci[i+1]]; var c: Vector3 = cv[ci[i+2]]
		area+=absf((b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x))*0.5
	checks["fine_mesh_retains_measured_height"]=conserved
	checks["mixed_lod_canonical_boundaries"]=stitched and absf(area-base.bounds.get_area())<0.01
	var previous: Array = TerrainDetailMesh.previous_shape(fine,coarse)
	var morph_edges := true
	for i in fine.arrays[Mesh.ARRAY_VERTEX].size():
		var v: Vector3 = fine.arrays[Mesh.ARRAY_VERTEX][i]
		var uv: Vector2 = (Vector2(v.x+base.origin.x,v.z+base.origin.z)-base.bounds.position)/base.bounds.size
		if uv.x==0 or uv.y==0 or uv.x==1 or uv.y==1: morph_edges=morph_edges and previous[Mesh.ARRAY_VERTEX][i]==v
	checks["morph_keeps_shared_edges_fixed"]=morph_edges
	var unchanged: String = result.hashes.collision
	graph.surface_style.tint_strength=0.8
	result=await build(builder,graph,region)
	checks["style_preserves_geometry_collision_and_cavity"]=result.hashes.collision==unchanged and result.cache_hits.has("collision") and result.cache_hits.has("shading") and not result.evaluated.has("imagery")
	var broken_shading: TerrainGenerationGraph = graph.duplicate(true)
	broken_shading.node("shading").operation="Unavailable cavity worker"
	var fallback_evaluator := TerrainGraphEvaluator.new()
	fallback_evaluator.artifacts.root_path=builder.evaluator.artifacts.root_path
	var fallback := fallback_evaluator.evaluate(broken_shading,builder.evaluator.context.duplicate())
	checks["optional_shading_failure_retains_sourced_patch"]=fallback.valid and fallback.cavity_image==null and not fallback.warnings.is_empty()
	graph.surface_style.tint_strength=0.62
	var prior_hash = result.hashes.collision
	graph.node("rocks").parameters.seed=999
	result=await build(builder,graph,region)
	checks["seed_change_preserves_terrain"]=result!=null and result.hashes.collision==prior_hash and result.cache_hits.has("collision") and result.evaluated.has("rocks") and not result.evaluated.has("imagery")
	graph.node("route").parameters.points=[Vector2(-20,-20),Vector2(20,20)]
	graph.node("route").parameters.origin="development_fixture"
	result=await build(builder,graph,region)
	var conforms = not result.route.arrays.is_empty()
	for point in result.route.arrays[Mesh.ARRAY_VERTEX]: conforms=conforms and absf(point.y-result.field.sample(point.x,point.z).height-0.07)<0.001
	checks["route_conforms_and_no_terrain_rebuild"]=conforms and result.cache_hits.has("collision")
	graph.node("route").parameters.points=[]
	graph.node("grid").parameters.spacing_m=8
	result=await build(builder,graph,region)
	checks["spacing_rebuilds_only_geometry_chain"]=result.evaluated.has("geometry") and result.evaluated.has("normals") and result.evaluated.has("collision") and result.cache_hits.has("height") and result.cache_hits.has("imagery")
	var malformed = graph.duplicate(true)
	malformed.node("geometry").inputs.field="grid"
	var ctx: Dictionary = builder.evaluator.context.duplicate()
	var rejection_evaluator := TerrainGraphEvaluator.new()
	rejection_evaluator.artifacts.root_path=builder.evaluator.artifacts.root_path
	var rejected = rejection_evaluator.evaluate(malformed,ctx)
	checks["wrong_port_type_rejected"]=not rejected.valid and not rejected.warnings.is_empty()
	graph=TerrainGenerationGraph.standard()
	graph.node("imagery").parameters.pixels=64
	graph.node("grid").parameters.spacing_m=16
	var global_ok = true
	for coordinate in [Vector2(18.44,77.45),Vector2(0,179.999),Vector2(89.999,-40),Vector2(-89.999,20)]:
		var cell = {"id":"test "+str(coordinate),"bounds":Rect2(coordinate.y-0.0078125,coordinate.x-0.0078125,0.015625,0.015625)}
		var other = TerrainMissionRegion.from_cell(cell,service)
		other.collar_m=16
		result=await build(builder,graph,other)
		global_ok=global_ok and result!=null and result.valid
		if result!=null: notes[str(coordinate)]={"sources":result.sources,"build_ms":result.build_ms,"size_m":str(other.size_m)}
	checks["same_pipeline_other_tiles_poles_and_seam"]=global_ok
	# Actual handoff into the rover scene, with an empty public route.
	region.latitude=-4.5895; region.longitude=137.4417
	graph.node("grid").parameters.spacing_m=4
	result=await build(builder,graph,region)
	var payload = {"result":result,"graph":graph,"service":service,"evaluator":builder.evaluator}
	root.set_meta("terrain_patch_handoff",payload)
	var world = load("res://procedural_terrain/mission.tscn").instantiate()
	root.add_child(world)
	current_scene=world
	var any_contact := false
	var ground := float(result.field.sample(0,0).height)
	var deadline := Time.get_ticks_msec()+2000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		any_contact=any_contact or world.rover.telemetry().wheels.any(func(wheel): return wheel.contacts>0)
	notes["settled_rover"]=world.rover.telemetry()
	notes["sampled_spawn_height"]=ground
	checks["rover_spawn_and_contact"]=any_contact and world.rover.chassis.global_position.is_finite() and absf(world.rover.chassis.global_position.y-ground)<2

	var initial: Vector3 = world.rover.chassis.global_position
	Input.action_press("forward")
	await create_timer(2.0).timeout
	Input.action_release("forward")
	checks["drive_on_generated_terrain"]=Vector2(world.rover.chassis.global_position.x,world.rover.chassis.global_position.z).distance_to(Vector2(initial.x,initial.z))>0.01 and absf(world.rover.chassis.global_position.y-initial.y)<1
	checks["public_route_absent"]=world.route_mesh==null
	var collision_id: int = world.terrain_root.get_child(0).get_child(1).shape.get_instance_id()
	world.set_source_appearance(true)
	checks["source_appearance_disables_cosmetics"]=not world.gravel_visual.visible and not bool(world.surface_materials[0].get_shader_parameter("cinematic"))
	world.set_source_appearance(false)
	checks["appearance_preserves_collision_identity"]=world.terrain_root.get_child(0).get_child(1).shape.get_instance_id()==collision_id
	notes["driven_rover"]=world.rover.telemetry()
	notes["chunk_count"]=result.chunks.size()
	notes["build_ms"]=result.build_ms
	print(JSON.stringify({"checks":checks,"measurements":notes}))
	FileAccess.open("res://evidence/procedural_checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"measurements":notes},"  "))
	world.free()
	builder.free()
	quit(1 if checks.values().has(false) else 0)
