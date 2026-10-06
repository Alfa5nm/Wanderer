extends "res://tests/dusty_capture.gd"

func run() -> void:
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1600,900); root.content_scale_size=root.size
	root.gui_disable_input=true
	var world: Node = load("res://procedural_terrain/mission.tscn").instantiate()
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+180000
	while not world.initialized_patch and Time.get_ticks_msec()<deadline: await process_frame
	if not world.initialized_patch: quit(1); return
	checks["default_exploration_6x"]=is_equal_approx(Engine.time_scale,6.0) and Engine.physics_ticks_per_second==720
	var height: float = world.result.field.sample(0,0).height
	checks["sourced_20km_horizon"]=world.result.chunks[-1].bounds.size.x>40000
	await create_timer(2.0).timeout
	var before: Vector3 = world.rover.chassis.global_position
	Input.action_press("forward")
	await create_timer(18.0).timeout
	Input.action_release("forward")
	world.tracks.flush()
	checks["rover_drives"]=world.rover.chassis.global_position.distance_to(before)>0.25
	checks["tracks_generated"]=world.tracks.total_segments>50 and not world.tracks.batches.is_empty()
	checks["bounded_tracks"]=world.tracks.batches.size()<=24
	var upward := true
	for batch in world.tracks.batches:
		for normal in batch.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]:
			upward=upward and normal.y>0
	checks["track_normals_face_sky"]=upward
	checks["near_gravel_streamed"]=world.close_gravel.tiles.size()==9
	checks["measured_height_unchanged"]=is_equal_approx(height,world.result.field.sample(0,0).height)
	world.set_sun_direction(Vector3(0.7,0.18,0.5).normalized())
	for size in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]:
		await shot("gameplay_tracks",size)
		measurements[str(size)]=await measure(world,3.0,true)
	world.set_source_appearance(true)
	await process_frame; await process_frame
	checks["source_hides_tracks_and_gravel"]=not world.tracks.visible and not world.close_gravel.visible
	await shot("gameplay_source",Vector2i(1600,900))
	world.set_source_appearance(false)
	world.accelerated=false; world.apply_mode()
	checks["engineering_120hz"]=Engine.time_scale==1 and Engine.physics_ticks_per_second==120
	world.pace=12; world.accelerated=true; world.apply_mode()
	checks["fast_travel_preserves_timestep"]=Engine.physics_ticks_per_second==1440
	measurements["12x_1600x900"]=await measure(world,3.0,false)
	world.accelerated=false; world.apply_mode()
	FileAccess.open("res://evidence/gameplay_polish.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"measurements":measurements},"  "))
	print(JSON.stringify({"checks":checks,"measurements":measurements}))
	world.queue_free(); await process_frame; await process_frame
	quit(1 if checks.values().has(false) else 0)
