extends SceneTree

func _initialize() -> void: call_deferred("run")

func wait_for_patch(globe: Node) -> Node:
	var deadline := Time.get_ticks_msec()+120000
	while (current_scene==null or current_scene==globe) and Time.get_ticks_msec()<deadline:
		if root.mode==Window.MODE_MINIMIZED: root.mode=Window.MODE_WINDOWED
		await process_frame
	if current_scene==null or current_scene==globe: return null
	return current_scene

func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1920,1080)
	root.gui_disable_input=true
	var globe: Node = load("res://planetary_map/mars_globe.tscn").instantiate()
	root.add_child(globe)
	current_scene=globe
	var checks := {}
	var started := Time.get_ticks_msec()
	globe.drive_bradbury()
	var world: Node = await wait_for_patch(globe)
	checks["bradbury_globe_handoff"]=world!=null
	if world==null:
		print("Terrain handoff failed: "+globe.hud.notice.text+" | building="+str(globe.patch_building)+" busy="+str(globe.patch_builder.busy)+" active="+str(globe.deployment.active)+" ready="+str(globe.deployment.ready_to_blend)+" packed="+str(globe.deployment.packed)+" tween="+str(globe.deployment.tween.get_total_elapsed_time())+" running="+str(globe.deployment.tween.is_running())+" paused="+str(paused)+" time_scale="+str(Engine.time_scale))
		quit(1); return
	await create_timer(1).timeout
	await capture("res://evidence/procedural_bradbury.png")
	world.settings_panel.visible=true
	await process_frame
	await capture("res://evidence/procedural_sources.png")
	checks["source_inspector"]=not world.information.text.is_empty()
	var first_build_ms: float = world.result.build_ms
	var full_handoff_ms := Time.get_ticks_msec()-started
	var initial: Vector3 = world.rover.chassis.position
	Input.action_press("forward")
	await create_timer(1).timeout
	Input.action_release("forward")
	checks["geographic_rover_moves"]=Vector2(world.rover.chassis.position.x,world.rover.chassis.position.z).distance_to(Vector2(initial.x,initial.z))>0.01
	world.return_to_mars()
	var deadline := Time.get_ticks_msec()+10000
	while (current_scene==null or current_scene==world) and Time.get_ticks_msec()<deadline: await process_frame
	globe=current_scene
	checks["return_to_globe"]=globe.get_script().resource_path=="res://planetary_map/globe.gd"
	globe.drive_bradbury()
	world=await wait_for_patch(globe)
	checks["repeat_bradbury_disk_reuse"]=world!=null and world.result.disk_hits.has("imagery") and world.result.disk_hits.has("collision")
	var warm_build_ms: float = world.result.build_ms if world!=null else -1
	if world==null: quit(1); return
	world.return_to_mars()
	deadline=Time.get_ticks_msec()+10000
	while (current_scene==null or current_scene==world) and Time.get_ticks_msec()<deadline: await process_frame
	globe=current_scene
	var cell := {"id":"Jezero capture","bounds":Rect2(77.4421875,18.4321875,0.015625,0.015625)}
	globe.survey.selected_cell=cell
	globe.show_cell(cell,false)
	globe.prepare_patch(TerrainMissionRegion.from_cell(cell,globe.surface_service))
	world=await wait_for_patch(globe)
	checks["survey_cell_handoff"]=world!=null
	if world!=null:
		await create_timer(1).timeout
		await capture("res://evidence/procedural_jezero.png")
		checks["jezero_mola_label"]=world.result.sources.has("MOLA 64 ppd")
	print(JSON.stringify({"checks":checks,"first_build_ms":first_build_ms,"warm_build_ms":warm_build_ms,"handoff_and_capture_ms":full_handoff_ms}))
	FileAccess.open("res://evidence/procedural_visual_checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"first_build_ms":first_build_ms,"warm_build_ms":warm_build_ms,"handoff_and_capture_ms":full_handoff_ms},"  "))
	quit(1 if checks.values().has(false) else 0)
