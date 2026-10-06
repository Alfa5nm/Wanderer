extends "res://tests/scout_capture.gd"
func run() -> void:
	root.mode=Window.MODE_WINDOWED; root.size=Vector2i(1600,900); root.content_scale_size=root.size
	var world: Node = load("res://procedural_terrain/mission.tscn").instantiate()
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+180000
	while not world.initialized_patch and Time.get_ticks_msec()<deadline: await process_frame
	if not world.initialized_patch: quit(1); return
	world.recording.prepare_scenario()
	deadline=Time.get_ticks_msec()+180000
	while (world.recording.worker!=null or world.recording.awaiting_region) and Time.get_ticks_msec()<deadline: await process_frame
	checks["scenario_ready"]=world.recording.scenario.get("ready",false)
	if not checks.scenario_ready: quit(1); return
	world.recording.select_shot(5)
	Input.action_press("forward")
	deadline=Time.get_ticks_msec()+25000
	while Time.get_ticks_msec()<deadline:
		var position: Vector3 = world.rover.chassis.position
		if Vector2(position.x,position.z).distance_to(world.recording.scenario.hazard)<8.5: break
		await process_frame
	Input.action_release("forward")
	deadline=Time.get_ticks_msec()+45000
	while (world.scout.worker!=null or world.scout.pending) and Time.get_ticks_msec()<deadline: await process_frame
	var route: Dictionary = world.scout.session.route
	checks["revised_from_proximity"]=route.state=="revised proposal" and not world.scout.session.findings.is_empty()
	if not checks.revised_from_proximity: quit(1); return
	var points: PackedVector2Array = route.points
	world.switch_actor()
	var actor: MarsAstronaut = world.astronaut
	var from: Vector3 = actor.position
	var began := Time.get_ticks_msec()
	Input.action_press("forward")
	for target in points:
		deadline=Time.get_ticks_msec()+7000
		while Time.get_ticks_msec()<deadline:
			var delta := target-Vector2(actor.position.x,actor.position.z)
			if delta.length()<0.3: break
			actor.camera_rig.yaw=atan2(delta.x,delta.y)
			if actor.state=="fallen": break
			await process_frame
		if actor.state=="fallen": break
	Input.action_release("forward"); await wall(0.4)
	checks["human_walked_revised_course"]=Vector2(actor.position.x,actor.position.z).distance_to(points[-1])<0.8 and actor.state!="fallen"
	checks["human_remains_1x"]=Engine.time_scale==1 and Engine.physics_ticks_per_second==120
	measurements["walk_seconds"]=float(Time.get_ticks_msec()-began)/1000
	measurements["walk_displacement_m"]=actor.position.distance_to(from)
	measurements["points"]=points.size(); measurements["planner_ms"]=world.scout.last_plan_ms
	await shot("walked_revised_course",Vector2i(1600,900))
	world.return_to_mars()
	deadline=Time.get_ticks_msec()+15000
	while current_scene==world and Time.get_ticks_msec()<deadline: await process_frame
	await wall(0.5)
	checks["session_projected_on_globe"]=current_scene!=world and current_scene.definition.markers.any(func(m): return m.id.begins_with("scout_"))
	var report := {"checks":checks,"measurements":measurements}
	FileAccess.open("res://evidence/scout_follow_route.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report)); current_scene.queue_free(); await process_frame; await process_frame
	quit(1 if checks.values().has(false) else 0)
