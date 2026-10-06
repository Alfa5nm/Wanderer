extends SceneTree

var globe: Node3D
var results: Dictionary = {}
var stage := ""
var samples: Array[float] = []
var previous_usec := 0
var orbiting := false

func settle(limit: float = 35.0) -> void:
	var elapsed := 0.0
	while elapsed<limit:
		await wait(0.25)
		elapsed+=0.25
		if globe.terrain.pending.is_empty() and globe.terrain.worker==null: break
	results["settle_"+str(results.size())]={"elapsed_s":elapsed,"patches":globe.terrain.patches.size(),"complete":globe.terrain.pending.is_empty() and globe.terrain.worker==null}

func wait_focus() -> void:
	var elapsed := 0.0
	while globe.rig.focusing and elapsed<5:
		await wait(0.1)
		elapsed+=0.1
	print("FOCUS ",globe.state," ",globe.rig.snapshot()," actual ",globe.rig.distance," focusing ",globe.rig.focusing)

func _initialize() -> void:
	call_deferred("run")

func _process(_dt: float) -> bool:
	var now := Time.get_ticks_usec()
	if previous_usec>0 and not stage.is_empty(): samples.append(float(now-previous_usec)/1000.0)
	previous_usec = now
	if orbiting and is_instance_valid(globe): globe.rig.yaw += 0.0008
	return false

func wait(seconds: float) -> void:
	await create_timer(seconds,true,false,true).timeout

func capture(label: String) -> Vector2i:
	var previous_stage := stage
	stage = ""
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var dimensions := image.get_size()
	image.save_png("res://evidence/"+label+".png")
	await process_frame
	previous_usec = 0
	stage = previous_stage
	return dimensions

func begin(label: String) -> void:
	stage = label
	samples.clear()
	previous_usec = 0

func finish() -> void:
	samples.sort()
	if not samples.is_empty():
		results[stage] = {"frames":samples.size(),"median_frame_ms":samples[samples.size()/2],"p95_frame_ms":samples[int(samples.size()*0.95)],"max_frame_ms":samples[-1]}
	stage = ""

func click(point: Vector2) -> void:
	globe.selection.dragging=false
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion,true)
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = true
	root.push_input(event,true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)

func run() -> void:
	globe = load("res://planetary_map/mars_globe.tscn").instantiate()
	root.add_child(globe)
	current_scene = globe
	globe.rig.locked=true
	await settle()
	root.borderless = true
	for resolution in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]:
		root.mode = Window.MODE_WINDOWED
		root.size = resolution
		root.position = Vector2i.ZERO
		await wait(0.5)
		var label := "%dx%d" % [resolution.x,resolution.y]
		globe.rig.yaw = deg_to_rad(80)
		globe.rig.pitch = deg_to_rad(12)
		globe.rig.distance = 3.4
		globe.rig.target_distance = 3.4
		globe.rig.velocity = Vector2.ZERO
		await settle()
		var dimensions: Vector2i = await capture("terrain_orbit_"+label)
		results["resolution_"+label] = {"window":str(root.size),"captured_pixels":str(dimensions),"exact":dimensions == resolution}
		begin("orbit_"+label)
		orbiting = true
		await wait(3)
		orbiting = false
		finish()
		globe.select_marker(globe.mission)
		await wait_focus()
		await settle()
		await capture("terrain_gale_"+label)
		var rectangle: Rect2 = globe.hud.panel.get_global_rect()
		results["panel_"+label] = {"inside_viewport":root.get_visible_rect().encloses(rectangle),"panel_rect":str(rectangle),"visible_rect":str(root.get_visible_rect())}
		await click(globe.hud.panel.explore.get_global_rect().get_center())
		await wait_focus()
		await settle()
		results["explore_click_"+label] = globe.state == globe.Navigation.MISSION_FOCUS and absf(globe.rig.distance-1.00065)<0.00002
		results["terrain_memory_"+label] = {"static_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576,"render_mb":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576}
		begin("local_"+label)
		await wait(3)
		finish()
		await capture("terrain_bradbury_"+label)
		globe.grid_toggle.button_pressed=true
		await wait(0.7)
		var point: Vector3 = globe.surface_service.position_at(-4.5895,137.4417)
		globe.survey.select_at(point)
		await wait(0.5)
		await capture("terrain_survey_"+label)
		results["cell_panel_"+label]=root.get_visible_rect().encloses(globe.cell_panel.get_global_rect())
		globe.go_back()
		globe.grid_toggle.button_pressed=false
		globe.go_back()
		globe.go_back()
		await wait(1)
	results["choose_max_ms_before_deployment"]=globe.terrain.choose_max_ms
	globe.select_marker(globe.mission)
	await wait(2)
	begin("deployment_including_scene_activation")
	await click(globe.hud.panel.deploy.get_global_rect().get_center())
	await wait(2.5)
	await capture("terrain_descent")
	await wait(4)
	finish()
	results["deployed"] = current_scene.scene_file_path == "res://main.tscn"
	await capture("terrain_deployed_rover")
	results["choose_max_ms"]=globe.terrain.choose_max_ms if is_instance_valid(globe) else -1
	results["adapter"] = RenderingServer.get_video_adapter_name()
	results["memory_static_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC)/1048576
	results["texture_dimensions"] = str(load("res://planetary_map/assets/mars_viking_4k.jpg").get_size())
	results["synthetic_input_note"] = "Mouse events injected through viewport; no physical controller hardware available. Timings include desktop presentation and capture overhead."
	FileAccess.open("res://evidence/terrain_visual_checks.json",FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	print(JSON.stringify(results))
	var failed: bool = not results.deployed
	for id in results:
		if id.begins_with("explore_click_") and not results[id]: failed = true
		if id.begins_with("resolution_") and not results[id].exact: failed = true
		if id.begins_with("cell_panel_") and not results[id]: failed = true
		if id.begins_with("panel_") and not results[id].inside_viewport: failed = true
	quit(1 if failed else 0)

