extends "res://tests/dusty_capture.gd"

func shot(name: String,size: Vector2i) -> Image:
	root.size=size; root.content_scale_size=size
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	rendered.save_png("res://evidence/scout_"+name+"_%dx%d.png" % [size.x,size.y])
	checks["render_size_"+str(size)]=rendered.get_size()==size
	return rendered

func wall(seconds: float) -> void: await create_timer(seconds,true,false,true).timeout

func run() -> void:
	print("SCOUT_CAPTURE_PID ",OS.get_process_id())
	root.mode=Window.MODE_WINDOWED; root.size=Vector2i(1600,900); root.content_scale_size=root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world: Node = load("res://procedural_terrain/mission.tscn").instantiate()
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+180000
	while not world.initialized_patch and Time.get_ticks_msec()<deadline: await process_frame
	if not world.initialized_patch: quit(1); return
	await wait_detail(world)
	world.set_sun_direction(Vector3(-0.35,0.7,-0.4))
	world.scout.enabled=false
	world.switch_actor(); await wall(0.5)
	var actor: MarsAstronaut = world.astronaut
	measurements["prepare_ms"]=world.result.build_ms
	for size in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]:
		await shot("astronaut",size)
		Input.action_press("forward")
		measurements["walking_"+str(size)]=await measure(world,3.0,false)
		Input.action_release("forward"); await wall(0.4)
	checks["foot_contact_measured"]=actor.metrics.contact_samples>0
	measurements["ik"]=actor.metrics.duplicate()
	checks["foot_target_error_under_5cm"]=actor.metrics.planted_drift_m<0.05
	actor.camera_rig.yaw=PI-0.3
	await wall(0.5)
	await shot("astronaut_front",Vector2i(1600,900))
	world.set_sun_direction(Vector3(-0.8,0.12,0.5))
	await shot("astronaut_low_sun",Vector2i(1600,900))
	world.set_sun_direction(Vector3(-0.8,-0.35,0.5))
	await shot("astronaut_night",Vector2i(1600,900))
	world.set_sun_direction(Vector3(-0.35,0.7,-0.4))
	world.switch_actor()
	world.recording.enabled=true
	world.recording.prepare_scenario()
	deadline=Time.get_ticks_msec()+180000
	while (world.recording.worker!=null or world.recording.awaiting_region) and Time.get_ticks_msec()<deadline: await process_frame
	checks["repeatable_scenario_ready"]=world.recording.scenario.get("ready",false)
	measurements["scenario"]=world.recording.scenario.duplicate()
	measurements.scenario.erase("risk_map"); measurements.scenario.erase("region")
	world.scout.enabled=true
	for i in 6:
		world.recording.select_shot(i)
		await wall(0.25)
		for size in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]: await shot("preset_%d" % (i+1),size)
		if i==1: await wall(4.0); await shot("map_entry_end",Vector2i(1600,900))
		if i==3:
			await wall(3.2); await shot("registered_imagery",Vector2i(1600,900))
			await wall(3.0); await shot("derived_slope",Vector2i(1600,900))
			await wall(3.0); await shot("science_destination",Vector2i(1600,900))
	if checks.repeatable_scenario_ready:
		Input.action_press("forward")
		deadline=Time.get_ticks_msec()+25000
		while Time.get_ticks_msec()<deadline:
			var p: Vector3 = world.rover.chassis.position
			if Vector2(p.x,p.z).distance_to(world.recording.scenario.hazard)<8.5: break
			await process_frame
		Input.action_release("forward")
		deadline=Time.get_ticks_msec()+45000
		while (world.scout.worker!=null or world.scout.pending) and Time.get_ticks_msec()<deadline: await process_frame
		checks["actual_proximity_discovers_hazard"]=world.scout.session.findings.values().any(func(f): return f.kind in ["simulated_obstacle","slope_hazard"])
		checks["feedback_revised_proposal"]=world.scout.session.route.state=="revised proposal"
		measurements["planner_ms"]=world.scout.last_plan_ms
		await shot("scout_feedback",Vector2i(1600,900))
		world.switch_actor(); await wall(0.5)
		await shot("human_handoff",Vector2i(1600,900))
		world.scout.enabled=false
		world.recording.reset_scenario(); await wall(0.3)
		checks["reset_restores_unverified"]=world.scout.session.route.state=="unverified proposal" and world.scout.session.findings.is_empty()
	measurements["adapter"]=RenderingServer.get_video_adapter_name()
	FileAccess.open("res://evidence/scout_capture_checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"measurements":measurements},"  "))
	print(JSON.stringify({"checks":checks,"measurements":measurements}))
	Engine.time_scale=1; Engine.physics_ticks_per_second=120
	world.queue_free(); await process_frame; await process_frame
	quit(1 if checks.values().has(false) else 0)
