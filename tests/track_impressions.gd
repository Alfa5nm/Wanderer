extends "res://tests/dusty_capture.gd"

func run() -> void:
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1600,900); root.content_scale_size=root.size
	root.gui_disable_input=true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var method := RenderingServer.get_current_rendering_method()
	var world: Node = load("res://procedural_terrain/mission.tscn").instantiate()
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+180000
	while not world.initialized_patch and Time.get_ticks_msec()<deadline: await process_frame
	if not world.initialized_patch: quit(1); return
	var collision_hash: String = world.result.hashes.collision
	Input.action_press("forward")
	await create_timer(48.0).timeout
	Input.action_press("right")
	await create_timer(8.0).timeout
	Input.action_release("right")
	Input.action_release("forward")
	Input.action_press("reverse")
	await create_timer(12.0).timeout
	Input.action_release("reverse")
	Input.action_press("brake")
	deadline=Time.get_ticks_msec()+60000
	while (world.tracks.worker!=null or world.tracks.tiles.size()<world.tracks.requested.size()) and Time.get_ticks_msec()<deadline: await process_frame
	world.tracks.flush()
	checks["dense_tiles_ready"]=world.tracks.tiles.size()>0 and world.tracks.tiles.size()==world.tracks.requested.size()
	checks["shared_single_mask"]=world.tracks.material.get_shader_parameter("track_mask")==world.surface_materials[0].get_shader_parameter("track_mask")
	checks["bounded_tiles"]=world.tracks.tiles.size()<=16
	checks["collision_unchanged"]=world.result.hashes.collision==collision_hash
	checks["centimetre_visual_mesh"]=world.tracks.CELLS==128 and world.tracks.TILE/world.tracks.CELLS<0.04
	world.set_sun_direction(Vector3(0.7,0.22,0.5).normalized())
	for size in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]:
		await shot("impressions_"+method,size)
	root.size=Vector2i(1600,900); root.content_scale_size=root.size
	measurements["moving_1600x900"]=await measure(world,5.0,true)
	var view := Camera3D.new()
	world.add_child(view)
	view.near=0.04; view.far=30000; view.fov=55
	var position: Vector3 = world.rover.chassis.global_position
	view.position=position+Vector3(-4,5,-3)
	view.look_at(position-Vector3(0,0,1),Vector3.UP)
	view.current=true
	await shot("impressions_overhead_"+method,Vector2i(1600,900))
	var target := Vector2.ZERO
	var deepest := 1.0
	for y in range(0,1024,4):
		for x in range(0,1024,4):
			var point: Vector2 = world.tracks.bounds.position+Vector2(x+0.5,y+0.5)*world.tracks.SPAN/world.tracks.PIXELS
			var value: Color = world.tracks.mask.get_pixel(x,y)
			if value.g<deepest and point.distance_to(Vector2(position.x,position.z))>1.5:
				deepest=value.g; target=point
	var height: float = world.result.field.sample(target.x,target.y).height
	view.position=Vector3(target.x-0.65,height+0.65,target.y-0.85)
	view.look_at(Vector3(target.x,height,target.y),Vector3.UP)
	await shot("impressions_close_"+method,Vector2i(1600,900))
	var negative := false; var positive := false
	for y in range(0,1024,3):
		for x in range(0,1024,3):
			var value: Color = world.tracks.mask.get_pixel(x,y)
			negative=negative or value.g<world.tracks.NEUTRAL-0.02
			positive=positive or value.g>world.tracks.NEUTRAL+0.02
	checks["actual_shallow_rut_and_shoulder"]=negative and positive
	var point := Vector2(position.x+3,position.z-3)
	world.tracks.stamp(point,point+Vector2(0,0.2),0.0)
	var before: PackedByteArray = world.tracks.mask.get_data()
	world.tracks.stamp(point,point+Vector2(0,0.2),0.0)
	checks["overlap_is_idempotent"]=before==world.tracks.mask.get_data()
	var minimum := 1.0; var maximum := 0.0
	for step in 10:
		var p := point+Vector2(0,0.015+step*0.015)
		var pixel: Vector2 = (p-world.tracks.bounds.position)/world.tracks.SPAN*world.tracks.PIXELS
		var height_mask: float = world.tracks.mask.get_pixel(int(pixel.x),int(pixel.y)).g
		minimum=minf(minimum,height_mask); maximum=maxf(maximum,height_mask)
	checks["tread_height_variation_survives_stamping"]=maximum-minimum>0.025
	world.set_source_appearance(true)
	await process_frame; await process_frame
	checks["source_restores_ground"]=not world.tracks.visible and not bool(world.surface_materials[0].get_shader_parameter("tracks_enabled"))
	await shot("impressions_source_"+method,Vector2i(1600,900))
	world.set_source_appearance(false)
	await process_frame
	checks["source_toggle_restores_marks"]=world.tracks.visible and bool(world.surface_materials[0].get_shader_parameter("tracks_enabled"))
	FileAccess.open("res://evidence/track_impressions_"+method+".json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"measurements":measurements},"  "))
	print(JSON.stringify({"checks":checks,"measurements":measurements}))
	Input.action_release("brake")
	Engine.time_scale=1; Engine.physics_ticks_per_second=120
	world.queue_free(); await process_frame; await process_frame
	quit(1 if checks.values().has(false) else 0)
