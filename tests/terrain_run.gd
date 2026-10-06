extends SceneTree

var checks: Dictionary = {}
var globe: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(id: String,value: bool) -> void:
	checks[id]=value
	if not value: push_error("FAIL: "+id)

func wait(seconds: float) -> void:
	await create_timer(seconds,true,false,true).timeout

func run() -> void:
	globe=load("res://planetary_map/mars_globe.tscn").instantiate()
	root.add_child(globe)
	current_scene=globe
	var service: PlanetSurfaceService = globe.surface_service
	check("numeric_global_core",service.manifest.get("mola",[]).size()==4 and service.overview.size()==1440*720*2)
	var sample := service.sample(-4.5895,137.4417)
	check("bradbury_valid_hirise",sample.valid and sample.source.begins_with("HiRISE") and sample.spacing_m<2)
	var source_samples = JSON.parse_string(FileAccess.get_file_as_string(PlanetSurfaceService.ROOT+"source_samples.json"))
	check("candidate_gap_recorded",source_samples is Array and source_samples[0].height_above_areoid_m==null)
	var areoid_x := int(137.4417*16)
	var areoid_y := int((90+4.5895)*16)
	var datum := service.areoid.decode_s16((areoid_y*5760+areoid_x)*2)
	check("datum_not_sphere_height",absf(sample.offset_m-(datum-4492.5088))<3)
	var high := service.sample(18,226)
	var low := service.sample(-42,70)
	check("real_relief",high.radial_m-low.radial_m>10000)
	check("longitude_periodic",absf(service.sample(10,-180).radial_m-service.sample(10,180).radial_m)<0.01)
	check("poles_finite",is_finite(service.sample(90,0).radial_m) and is_finite(service.sample(-90,270).radial_m))
	check("invalid_data_rejected",not service.sample(100,0).valid)
	var point := service.position_at(-4.5895,137.4417)
	var hit := service.hit(point.normalized()*1.2,-point.normalized())
	check("terrain_ray",hit.distance_to(point)<0.000002)
	check("terrain_front_visible",not service.occluded(point.normalized()*1.2,service.position_at(-4.5895,137.4417,5)))
	check("terrain_back_occluded",service.occluded(-point.normalized()*1.2,point))
	var detail := PlanetDataset.new()
	detail.bounds=Rect2(0,0,1,1)
	detail.width=2; detail.height=2; detail.loaded=true
	detail.heights=PackedFloat32Array([0,2,4,6])
	check("bilinear_height",absf(detail.elevation(0.5,0.5)-3)<0.00001)
	detail.heights[0]=NAN
	check("invalid_mask_no_interpolation",not is_finite(detail.elevation(0.5,0.5)))
	var roundtrips := true
	for face in 6:
		for u in [-0.8,0.0,0.8]:
			for v in [-0.8,0.0,0.8]:
				var mapped := PlanetTerrainRenderer.face_uv(PlanetTerrainRenderer.direction(face,u,v))
				roundtrips=roundtrips and int(mapped.x)==face and absf(mapped.y-u)<0.00001 and absf(mapped.z-v)<0.00001
	check("cube_face_roundtrip",roundtrips)
	var seams := true
	for face in 6:
		for p in [Vector2(-1,0.25),Vector2(1,-0.25),Vector2(0.25,-1),Vector2(-0.25,1)]:
			var direction := PlanetTerrainRenderer.direction(face,p.x,p.y)
			var mapped := PlanetTerrainRenderer.face_uv(direction)
			seams=seams and direction.distance_to(PlanetTerrainRenderer.direction(int(mapped.x),mapped.y,mapped.z))<0.000001
	check("shared_cube_edges",seams)
	globe.rig.focus_on_coordinates(-4.5895,137.4417,1.00065,0.1)
	await globe.rig.focus_finished
	await process_frame
	await process_frame
	print("CLOSE VIEW ",globe.rig.distance," ",globe.rig.camera.near," ",globe.rig.camera.global_position)
	check("camera_rebased",globe.rig.camera.global_position.length()<0.000001)
	check("adaptive_near_clip",globe.rig.camera.near/PlanetCameraRig.RENDER_SCALE<0.00001)
	globe.survey.set_enabled(true)
	globe.survey.select_at(point)
	check("cell_selected",globe.cell_open and globe.cell_panel.visible)
	var cell: Dictionary = globe.survey.selected_cell.duplicate(true)
	check("geographic_footprint",cell.bounds.has_point(Vector2(137.4417,-4.5895)))
	var coverage: Dictionary = globe.survey.coverage(cell)
	check("truthful_local_coverage",not coverage.loaded.is_empty() and not coverage.published.is_empty())
	var valid_faded_pixel := false
	for data in service.datasets:
		if data.id!="hirise_bradbury_image": continue
		for y in range(32,data.height,64):
			for x in range(32,data.width,64):
				var alpha: float = data.image.get_pixel(x,y).a
				if alpha<=0 or alpha>=0.5: continue
				var lon: float = data.bounds.position.x+(float(x)+0.5)/data.width*data.bounds.size.x
				var lat: float = data.bounds.end.y-(float(y)+0.5)/data.height*data.bounds.size.y
				if data.imagery_valid(lat,lon): valid_faded_pixel=true
	check("coverage_independent_of_display_fade",valid_faded_pixel)
	var previous_state: int = globe.state
	globe.go_back()
	check("cell_cancel_preserves_navigation",not globe.cell_open and globe.state==previous_state)
	globe.streamer.offline=true
	globe.streamer.request_cell(cell.bounds)
	check("offline_no_worker",globe.streamer.pid<0 and globe.streamer.queue.is_empty())
	var event := InputEventJoypadButton.new()
	event.button_index=JOY_BUTTON_A
	event.pressed=true
	root.push_input(event,true)
	await process_frame
	check("controller_cell_pick",globe.cell_open)
	event=event.duplicate()
	event.button_index=JOY_BUTTON_B
	root.push_input(event,true)
	await process_frame
	check("controller_cell_cancel",not globe.cell_open)
	var balanced := true
	var leaves: Array[Dictionary] = []
	for leaf in globe.terrain.desired.values(): leaves.append(leaf)
	for leaf in leaves:
		var width := 2.0/pow(2.0,leaf.level)
		for edge in [Vector2(-0.001,0.5),Vector2(1.001,0.5),Vector2(0.5,-0.001),Vector2(0.5,1.001)]:
			var neighbour := PlanetTerrainRenderer.find_leaf(PlanetTerrainRenderer.direction(leaf.face,-1+(leaf.x+edge.x)*width,-1+(leaf.y+edge.y)*width),leaves)
			balanced=balanced and not neighbour.is_empty() and absi(neighbour.level-leaf.level)<=1
	check("adjacent_lod_balance",balanced)
	var fixture: Dictionary = globe.terrain.build_patch({"face":0,"level":4,"x":8,"y":8,"edges":[true,false,false,false]})
	var vertices: PackedVector3Array = fixture.arrays[Mesh.ARRAY_VERTEX]
	var stride := PlanetTerrainRenderer.SEGMENTS+1
	check("coarse_edge_stitch",vertices[stride].distance_to((vertices[0]+vertices[2*stride])*0.5)<0.0000001)
	check("morph_attributes",fixture.arrays[Mesh.ARRAY_COLOR].size()==vertices.size())
	var transform := Transform3D(Basis.from_euler(Vector3(0.2,0.7,-0.1)).scaled(Vector3.ONE*3),Vector3(10,4,-7))
	var recovered := transform.affine_inverse()*(transform*point)
	check("transformed_terrain_position",recovered.distance_to(point)<0.000002)
	check("terrain_normals_outward",service.normal_at(-4.5895,137.4417).dot(point.normalized())>0.5)
	var invalid := {"id":"invalid","bounds":[0,0,0,1],"width":2,"height":2}
	check("invalid_dataset_rejected",service.add_dataset(invalid)==null)
	await wait(3)
	check("terrain_mesh_uploads",globe.terrain.uploads>6)
	check("no_spherical_surface_mesh",globe.surface.mesh==null)
	var counts := {"mission":0}
	for data in globe.definition.markers:
		if data.category=="mission": counts.mission+=1
	check("eight_sourced_anchors",counts.mission==8)
	FileAccess.open("res://evidence/terrain_checks.json",FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
	print(JSON.stringify(checks))
	var failed := false
	for value in checks.values(): failed=failed or not value
	globe.queue_free()
	await process_frame
	quit(1 if failed else 0)

