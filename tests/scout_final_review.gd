extends "res://tests/scout_capture.gd"

func run() -> void:
	root.mode=Window.MODE_WINDOWED; root.size=Vector2i(1600,900); root.content_scale_size=root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world: Node = load("res://procedural_terrain/mission.tscn").instantiate()
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+180000
	while not world.initialized_patch and Time.get_ticks_msec()<deadline: await process_frame
	if not world.initialized_patch: quit(1); return
	await wait_detail(world)
	world.scout.enabled=false
	world.switch_actor(); await wall(0.5)
	world.set_sun_direction(Vector3(-0.35,0.7,-0.4))
	world.astronaut.camera_rig.yaw=PI-0.3; world.astronaut.camera_rig.distance=3.5
	await wall(0.5)
	for size in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]:
		await shot("final_emu",size)
		Input.action_press("forward")
		measurements["sustained_walk_"+str(size)]=await measure(world,8.0,false)
		Input.action_release("forward"); await wall(0.4)
	checks["stable_contacts"]=world.astronaut.metrics.planted_drift_m<0.05
	measurements["ik"]=world.astronaut.metrics.duplicate()
	world.switch_actor()
	world.scout.propose(Vector2(-5,0),Vector2(5,0)); world.scout.replan()
	measurements["during_worker_plan"]=await measure(world,9.0,false)
	deadline=Time.get_ticks_msec()+30000
	while world.scout.worker!=null and Time.get_ticks_msec()<deadline: await process_frame
	checks["final_planner_returns"]=world.scout.worker==null
	measurements["planner_ms"]=world.scout.last_plan_ms
	world.recording.select_shot(4)
	checks["capture_hud_retracted"]=not world.scout_presentation.map.get_parent().visible and not world.recording.panel.visible
	for size in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]: await shot("final_provenance",size)
	world.recording.select_shot(5)
	checks["handoff_map_visible"]=world.scout_presentation.map.get_parent().visible and not world.recording.panel.visible
	await shot("final_handoff",Vector2i(1600,900))
	measurements["adapter"]=RenderingServer.get_video_adapter_name()
	FileAccess.open("res://evidence/scout_final_review.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"measurements":measurements},"  "))
	print(JSON.stringify({"checks":checks,"measurements":measurements}))
	Engine.time_scale=1; Engine.physics_ticks_per_second=120
	world.queue_free(); await process_frame; await process_frame
	quit(1 if checks.values().has(false) else 0)
