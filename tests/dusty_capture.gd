extends "res://tests/detail_capture.gd"

func measure(world: Node,seconds: float,moving: bool) -> Dictionary:
	var samples: Array[float] = []
	var last: int = Time.get_ticks_usec()
	var deadline: int = Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		await process_frame
		var now: int = Time.get_ticks_usec()
		var frame_ms := float(now-last)/1000.0
		if moving: world.orbit.yaw+=0.7*minf(frame_ms/1000,0.05)
		samples.append(frame_ms); last=now
	samples.sort()
	return {"p50_ms":samples[samples.size()/2],"p95_ms":samples[int(samples.size()*0.95)],"max_ms":samples[-1],"frames":samples.size(),"pixels":str(root.size),"static_memory_mib":float(Performance.get_monitor(Performance.MEMORY_STATIC))/1048576,"texture_memory_mib":float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))/1048576,"detail":world.detail.metrics.duplicate()}

func shot(name: String,size: Vector2i) -> Image:
	root.size=size
	root.content_scale_size=size
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("res://evidence/dusty_"+name+"_%dx%d.png" % [size.x,size.y])
	checks["render_size_"+str(size)]=image.get_size()==size
	return image

func run() -> void:
	print("DUSTY_PID ",OS.get_process_id())
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1920,1080); root.content_scale_size=root.size
	root.gui_disable_input=true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var globe: Node = load("res://planetary_map/mars_globe.tscn").instantiate()
	root.add_child(globe); current_scene=globe
	checks["compatibility_preserved"]=RenderingServer.get_current_rendering_method()=="gl_compatibility"
	checks["shared_orbital_profile"]=globe.terrain.atmosphere.material_override.get_shader_parameter("dust_transport")!=null
	var boot_deadline := Time.get_ticks_msec()+45000
	while not globe.terrain.roots_ready and Time.get_ticks_msec()<boot_deadline: await process_frame
	await create_timer(1.0).timeout
	await shot("orbit",Vector2i(1920,1080))
	globe.patch_builder.evaluator.artifacts.root_path="user://dusty_verification/"
	DirAccess.make_dir_recursive_absolute(globe.patch_builder.evaluator.artifacts.root_path)
	if "--warm-capture" not in OS.get_cmdline_user_args():
		for name in DirAccess.get_files_at(globe.patch_builder.evaluator.artifacts.root_path):
			if name.begins_with("patch_"): DirAccess.remove_absolute(globe.patch_builder.evaluator.artifacts.root_path+name)
	globe.drive_bradbury()
	var world: Node = await patch(globe)
	if world==null: checks["bradbury_deployment"]=false; quit(1); return
	measurements["initial_prepare_ms"]=world.result.build_ms
	measurements["initial_cache_mode"]="warm" if "--warm-capture" in OS.get_cmdline_user_args() else "cold"
	if "--repair-smoke" in OS.get_cmdline_user_args():
		await wait_detail(world)
		world.set_sun_direction(Vector3(-0.35,0.70,-0.4))
		checks["mapped_detail_ready"]=bool(world.surface_materials[0].get_shader_parameter("detail_maps_ready"))
		checks["transport_ready"]=bool(world.patch_lighting.sky_material.get_shader_parameter("has_dust_transport"))
		Engine.time_scale=40
		await process_frame
		await process_frame
		checks["dust_uses_wall_time"]=is_equal_approx(world.dust.sheets.speed_scale,0.025)
		Engine.time_scale=1
		if "--walltime-only" in OS.get_cmdline_user_args():
			FileAccess.open("res://evidence/dusty_walltime_checks.json",FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
			print(JSON.stringify(checks))
			world.queue_free(); await process_frame; await process_frame
			quit(1 if checks.values().has(false) else 0)
			return
		world.set_graphics_quality(0)
		await create_timer(0.4).timeout
		measurements["performance_preset_1920x1080"]=await measure(world,10.0,true)
		world.orbit.reset_view()
		world.set_graphics_quality(1)
		await create_timer(0.3).timeout
		await shot("final_smoke",Vector2i(1920,1080))
		world.surface_materials[0].set_shader_parameter("detail_maps_ready",false)
		world.patch_lighting.sky_material.set_shader_parameter("has_dust_transport",false)
		await shot("optional_map_fallback",Vector2i(1600,900))
		checks["fallback_retains_geometry"]=world.result.valid
		FileAccess.open("res://evidence/dusty_repair_checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"measurements":measurements},"  "))
		print(JSON.stringify({"checks":checks,"measurements":measurements}))
		world.queue_free(); await process_frame; await process_frame
		quit(1 if checks.values().has(false) else 0)
		return
	for target in ["bradbury","jezero","mola"]:
		if target!="bradbury":
			var point := Vector2(18.44,77.45) if target=="jezero" else Vector2(0,179.999)
			var cell := {"id":target,"bounds":Rect2(point.y-0.0078125,point.x-0.0078125,0.015625,0.015625)}
			globe.prepare_patch(TerrainMissionRegion.from_cell(cell,globe.surface_service))
			world=await patch(globe)
			if world==null: checks[target+"_deployment"]=false; quit(1); return
		checks[target+"_deployment"]=true
		await wait_detail(world)
		var body: Node = world.terrain_root.get_child(0)
		var collision_id: int = body.get_child(1).shape.get_instance_id()
		var height: float = world.result.field.sample(0,0).height
		var hashes: Dictionary = world.result.hashes.duplicate()
		world.set_sun_direction(Vector3(-0.35,0.70,-0.4))
		checks[target+"_daylight_sky_fill"]=world.patch_lighting.environment.ambient_light_energy>0
		checks[target+"_same_sun_in_haze"]=world.patch_lighting.haze.material_override.get_shader_parameter("sun_direction")==world.patch_lighting.settings.sun_direction
		world.set_atmosphere_strength(1.35)
		world.set_graphics_quality(1)
		for phase in [{"name":"day","sun":Vector3(-0.35,0.70,-0.4)}, {"name":"low_sun","sun":Vector3(-0.8,0.12,0.5)}, {"name":"twilight","sun":Vector3(-0.8,-0.025,0.5)}, {"name":"night","sun":Vector3(-0.8,-0.35,0.5)}]:
			world.set_sun_direction(phase.sun)
			await create_timer(0.4).timeout
			for size in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]:
				var rendered: Image = await shot(target+"_"+phase.name,size)
				if phase.name=="day":
					var sky_color := rendered.get_pixel(size.x/2,20)
					checks[target+"_day_sky_readable_"+str(size)]=sky_color.r>0.25
				if phase.name=="night":
					var ground_color := rendered.get_pixel(int(size.x*0.25),int(size.y*0.65))
					checks[target+"_rendered_night_dark_"+str(size)]=maxf(ground_color.r,maxf(ground_color.g,ground_color.b))<0.01
		checks[target+"_night_has_zero_fill"]=world.patch_lighting.environment.ambient_light_energy==0 and world.patch_lighting.sun.light_energy==0
		checks[target+"_night_dust_hidden"]=not world.dust.sheets.visible
		world.set_sun_direction(Vector3(-0.8,0.18,0.5))
		show_surface(world)
		for size in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]: await shot(target+"_close",size)
		world.set_source_appearance(true)
		await create_timer(0.3).timeout
		checks[target+"_source_hides_cosmetic_dust"]=not world.dust.sheets.visible and not world.gravel_visual.visible
		await shot(target+"_source",Vector2i(1600,900))
		world.set_source_appearance(false)
		world.set_atmosphere_strength(0.45)
		await shot(target+"_clear",Vector2i(1600,900))
		world.set_atmosphere_strength(1.35)
		for quality in 3: world.set_graphics_quality(quality); await process_frame
		checks[target+"_quality_changes_no_geometry"]=world.result.hashes==hashes and body.get_child(1).shape.get_instance_id()==collision_id and world.result.field.sample(0,0).height==height
		world.set_graphics_quality(1)
		if target=="bradbury":
			await shot("filmic",Vector2i(1600,900))
			world.patch_lighting.environment.tonemap_mode=Environment.TONE_MAPPER_AGX
			await shot("agx",Vector2i(1600,900))
			world.patch_lighting.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
			world.settings_scroll.visible=true; world.settings_panel.visible=true
			await shot("settings",Vector2i(1366,768))
			world.settings_scroll.visible=false; world.settings_panel.visible=false
		current_camera.queue_free()
		world.orbit.camera.current=true
		world.set_sun_direction(Vector3(-0.35,0.70,-0.4))
		world.orbit.distance=80
		await create_timer(0.6).timeout
		await shot(target+"_distant",Vector2i(1600,900))
		world.orbit.reset_view()
		await create_timer(0.4).timeout
		if target=="bradbury":
			for size in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]:
				root.size=size; root.content_scale_size=size
				await create_timer(0.4).timeout
				measurements[target+"_navigation_"+str(size)]=await measure(world,10.0,true)
		else: measurements[target+"_navigation"]=await measure(world,10.0,true)
		var initial: Vector3 = world.rover.chassis.position
		Input.action_press("forward")
		await create_timer(1.2).timeout
		Input.action_release("forward")
		checks[target+"_rover_drives"]=world.rover.chassis.position.distance_to(initial)>0.01
		world.overhead.position=Vector3(0,height+500,0)
		world.overhead.look_at(Vector3(0,height,0),Vector3.FORWARD); world.overhead.current=true
		await shot(target+"_overhead",Vector2i(1600,900))
		globe=await return_globe(world)
		globe.patch_builder.evaluator.artifacts.root_path="user://dusty_verification/"
	globe.drive_bradbury()
	world=await patch(globe)
	checks["repeat_deployment"]=world!=null and world.result.disk_hits.has("collision")
	if world!=null:
		measurements["warm_prepare_ms"]=world.result.build_ms
		checks["atmosphere_persists_deployment"]=world.patch_lighting.settings.atmosphere.strength==1.35
	measurements["adapter"]=RenderingServer.get_video_adapter_name()
	FileAccess.open("res://evidence/dusty_visual_checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"measurements":measurements},"  "))
	print(JSON.stringify({"checks":checks,"measurements":measurements}))
	current_scene.queue_free(); await process_frame; await process_frame
	quit(1 if checks.values().has(false) else 0)
