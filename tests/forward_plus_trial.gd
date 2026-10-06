extends "res://tests/dusty_capture.gd"

func run() -> void:
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1600,900); root.content_scale_size=root.size
	root.gui_disable_input=true
	var method := RenderingServer.get_current_rendering_method()
	print("RENDERER_TRIAL ",method)
	checks["expected_renderer"]=method==("gl_compatibility" if "--compatibility-check" in OS.get_cmdline_user_args() else "forward_plus")
	var globe: Node = load("res://planetary_map/mars_globe.tscn").instantiate()
	root.add_child(globe); current_scene=globe
	var deadline := Time.get_ticks_msec()+45000
	while not globe.terrain.roots_ready and Time.get_ticks_msec()<deadline: await process_frame
	checks["orbital_roots_ready"]=globe.terrain.roots_ready
	await create_timer(1.0).timeout
	await shot("renderer_orbit_"+method,Vector2i(1600,900))
	if "--orbit-lab-only" in OS.get_cmdline_user_args():
		globe.queue_free(); await process_frame; await process_frame
		var original: Node = load("res://main.tscn").instantiate()
		root.add_child(original); current_scene=original
		await create_timer(6.0).timeout
		checks["original_field_lab_ready"]=is_instance_valid(original.rover.chassis)
		await shot("renderer_original_lab_"+method,Vector2i(1600,900))
		FileAccess.open("res://evidence/renderer_orbit_lab_"+method+".json",FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
		print(JSON.stringify(checks))
		original.queue_free(); await process_frame; await process_frame
		Engine.time_scale=1; Engine.physics_ticks_per_second=120
		quit(1 if checks.values().has(false) else 0)
		return
	globe.drive_bradbury()
	var world: Node = await patch(globe)
	checks["local_deployment"]=world!=null
	if world==null: print(JSON.stringify(checks)); quit(1); return
	await create_timer(6.0).timeout
	checks["native_fog_only_forward"]=world.patch_lighting.environment.volumetric_fog_enabled==(method=="forward_plus")
	var hashes: Dictionary = world.result.hashes.duplicate()
	var origin: Vector3 = world.rover.chassis.global_position
	Input.action_press("forward")
	await create_timer(18.0).timeout
	Input.action_release("forward")
	checks["rover_drive"]=world.rover.chassis.global_position.distance_to(origin)>0.25
	world.set_sun_direction(Vector3(0.7,0.18,0.5).normalized())
	for size in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]:
		await shot("renderer_dust_"+method,size)
		measurements[str(size)]=await measure(world,5.0,true)
	world.patch_lighting.set_native_fog(false)
	checks["native_fog_switch_off"]=not world.patch_lighting.environment.volumetric_fog_enabled
	await shot("renderer_no_native_"+method,Vector2i(1600,900))
	measurements["no_native_1600x900"]=await measure(world,5.0,false)
	world.patch_lighting.set_native_fog(true)
	world.set_source_appearance(true)
	checks["appearance_preserves_geometry"]=world.result.hashes==hashes
	await shot("renderer_source_"+method,Vector2i(1600,900))
	world.set_sun_direction(Vector3(0.7,-0.3,0.5).normalized())
	checks["night_direct_and_fill_zero"]=world.patch_lighting.sun.light_energy==0 and world.patch_lighting.environment.ambient_light_energy==0
	if method=="forward_plus": checks["night_no_glowing_fog"]=world.patch_lighting.environment.volumetric_fog_density==0
	await shot("renderer_night_"+method,Vector2i(1600,900))
	world.set_sun_direction(Vector3(0.7,0.18,0.5).normalized())
	world.set_source_appearance(false)
	checks["default_project_still_compatibility"]=ProjectSettings.get_setting("rendering/renderer/rendering_method")=="gl_compatibility"
	FileAccess.open("res://evidence/renderer_trial_"+method+".json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"measurements":measurements},"  "))
	print(JSON.stringify({"checks":checks,"measurements":measurements}))
	Engine.time_scale=1; Engine.physics_ticks_per_second=120
	world.queue_free(); await process_frame; await process_frame
	var lab: Node = load("res://main.tscn").instantiate()
	root.add_child(lab); current_scene=lab
	await create_timer(6.0).timeout
	checks["original_field_lab_ready"]=is_instance_valid(lab.rover.chassis)
	await shot("renderer_original_lab_"+method,Vector2i(1600,900))
	FileAccess.open("res://evidence/renderer_trial_"+method+".json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"measurements":measurements},"  "))
	lab.queue_free(); await process_frame; await process_frame
	Engine.time_scale=1; Engine.physics_ticks_per_second=120
	quit(1 if checks.values().has(false) else 0)
