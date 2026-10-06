extends "res://tests/scout_capture.gd"
func run() -> void:
	root.mode=Window.MODE_WINDOWED; root.size=Vector2i(1600,900); root.content_scale_size=root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world: Node = load("res://procedural_terrain/mission.tscn").instantiate()
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+180000
	while not world.initialized_patch and Time.get_ticks_msec()<deadline: await process_frame
	if not world.initialized_patch: quit(1); return
	await wait_detail(world); world.scout.enabled=false
	world.set_sun_direction(Vector3(-0.35,0.7,-0.4)); world.switch_actor()
	world.astronaut.camera_rig.yaw=PI-0.3; world.astronaut.camera_rig.distance=3.5
	await wall(0.4)
	for size in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]: await shot("release_emu",size)
	root.size=Vector2i(1600,900); root.content_scale_size=root.size
	Input.action_press("forward"); measurements["final_walk_1600x900"]=await measure(world,12.0,false)
	Input.action_release("forward"); await wall(0.4)
	checks["final_foot_lock"]=world.astronaut.metrics.planted_drift_m<0.05
	measurements["ik"]=world.astronaut.metrics.duplicate()
	world.switch_actor()
	var before: String = world.result.hashes.collision
	world.recording.scenario={"ready":true,"kind":"SIMULATED OBSTACLE","start":Vector2(39.68254,0.881744),"goal":Vector2(39.68254,18.881744)}
	world.recording.select_shot(0); world.recording.reset_scenario(); await wall(0.2)
	checks["reset_restores_camera"]=world.orbit.camera.current and world.recording.stage==0
	checks["reset_without_terrain_rebuild"]=before==world.result.hashes.collision and not world.builder.busy
	checks["reset_proposal"]=world.scout.session.route.state=="unverified proposal" and world.scout.session.findings.is_empty()
	world.recording.awaiting_region=true; world.builder.failed.emit("Injected preparation failure")
	checks["preparation_failure_keeps_ready_patch"]=not world.recording.awaiting_region and world.initialized_patch and world.result.hashes.collision==before
	world.recording.select_shot(4)
	for size in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]: await shot("release_provenance",size)
	var report := {"checks":checks,"measurements":measurements}
	FileAccess.open("res://evidence/scout_release_smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report)); Engine.time_scale=1; Engine.physics_ticks_per_second=120
	world.queue_free(); await process_frame; await process_frame
	quit(1 if checks.values().has(false) else 0)
