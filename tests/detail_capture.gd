extends SceneTree

var checks: Dictionary = {}
var measurements: Dictionary = {}
var current_camera: Camera3D

func _initialize() -> void: call_deferred("run")

func patch(globe: Node) -> Node:
	var deadline: int = Time.get_ticks_msec()+180000
	while (current_scene==null or current_scene==globe) and Time.get_ticks_msec()<deadline:
		if root.mode==Window.MODE_MINIMIZED: root.mode=Window.MODE_WINDOWED
		await process_frame
	return current_scene if current_scene!=null and current_scene!=globe else null

func wait_detail(world: Node) -> void:
	var deadline: int = Time.get_ticks_msec()+35000
	while (world.detail.estimates.is_empty() or world.detail.metrics.uploads<2) and Time.get_ticks_msec()<deadline: await process_frame
	await create_timer(0.5).timeout

func shot(name: String,size: Vector2i) -> Image:
	root.size=size
	root.content_scale_size=size
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("res://evidence/detail_"+name+"_%dx%d.png" % [size.x,size.y])
	checks["render_size_"+str(size)]=image.get_size()==size
	return image

func measure(world: Node,seconds: float,moving: bool) -> Dictionary:
	var samples: Array[float] = []
	var last: int = Time.get_ticks_usec()
	var deadline: int = Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if moving: world.orbit.yaw+=0.035
		await process_frame
		var now: int = Time.get_ticks_usec()
		samples.append(float(now-last)/1000); last=now
	samples.sort()
	return {"p50_ms":samples[samples.size()/2],"p95_ms":samples[int(samples.size()*0.95)],"max_ms":samples[-1],"frames":samples.size(),"static_memory_mib":float(Performance.get_monitor(Performance.MEMORY_STATIC))/1048576,"texture_memory_mib":float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))/1048576,"detail":world.detail.metrics.duplicate()}

func show_surface(world: Node) -> void:
	current_camera=Camera3D.new()
	world.add_child(current_camera)
	current_camera.near=0.04; current_camera.far=4000; current_camera.fov=60
	var h: float = world.result.field.sample(8,8).height
	current_camera.position=Vector3(8,h+0.40,10)
	current_camera.look_at(Vector3(8,h,7),Vector3.UP)
	current_camera.current=true

func sun(world: Node,direction: Vector3) -> void:
	world.set_sun_direction(direction)

func return_globe(world: Node) -> Node:
	world.return_to_mars()
	var deadline: int = Time.get_ticks_msec()+15000
	while (current_scene==null or current_scene==world) and Time.get_ticks_msec()<deadline: await process_frame
	return current_scene

func run() -> void:
	print("DETAIL_PID ",OS.get_process_id())
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1920,1080); root.content_scale_size=root.size
	root.gui_disable_input=true
	var globe: Node = load("res://planetary_map/mars_globe.tscn").instantiate()
	root.add_child(globe); current_scene=globe
	globe.patch_builder.evaluator.artifacts.root_path="user://detail_visual_verification/"
	DirAccess.make_dir_recursive_absolute(globe.patch_builder.evaluator.artifacts.root_path)
	for name in DirAccess.get_files_at(globe.patch_builder.evaluator.artifacts.root_path):
		if "--shadow-diagnostic" not in OS.get_cmdline_user_args() and name.begins_with("patch_"): DirAccess.remove_absolute(globe.patch_builder.evaluator.artifacts.root_path+name)
	globe.drive_bradbury()
	var world: Node = await patch(globe)
	checks["bradbury_deployment"]=world!=null
	if world==null: print(JSON.stringify(checks)); quit(1); return
	measurements["first_build_ms"]=world.result.build_ms
	await wait_detail(world)
	if "--shadow-diagnostic" in OS.get_cmdline_user_args():
		world.set_source_appearance(true)
		await shot("diagnostic_original_shadows",Vector2i(1600,900))
		world.patch_lighting.sun.shadow_enabled=false
		await shot("diagnostic_without_shadows",Vector2i(1600,900))
		world.patch_lighting.sun.shadow_enabled=true
		world.patch_lighting.sun.shadow_bias=0.12
		world.patch_lighting.sun.shadow_normal_bias=2.0
		await shot("diagnostic_bias",Vector2i(1600,900))
		world.patch_lighting.sun.light_angular_distance=0
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		await shot("diagnostic_hard_shadow",Vector2i(1600,900))
		world.queue_free(); await process_frame; await process_frame; quit(); return
	checks["progressive_visual_refinement"]=not world.detail.estimates.is_empty() and world.detail.metrics.uploads>0
	var shape_id: int = world.terrain_root.get_child(0).get_child(1).shape.get_instance_id()
	measurements["bradbury_navigation"]=await measure(world,2.0,true)
	var morph_modes := true
	for visual in world.detail.visuals.values():
		if visual.mesh.get_blend_shape_count()>0: morph_modes=morph_modes and visual.mesh.blend_shape_mode==Mesh.BLEND_SHAPE_MODE_NORMALIZED
	checks["normalized_morph_mode"]=morph_modes
	checks["refinement_keeps_collision"]=world.terrain_root.get_child(0).get_child(1).shape.get_instance_id()==shape_id
	world.orbit.reset_view()
	await create_timer(0.4).timeout
	for size in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]:
		await shot("bradbury_rover",size)
	world.settings_panel.visible=true
	await shot("settings",Vector2i(1366,768))
	world.settings_panel.visible=false
	show_surface(world)
	var cinematic: Image = await shot("bradbury_close",Vector2i(1920,1080))
	world.set_source_appearance(true)
	var observed: Image = await shot("bradbury_source",Vector2i(1920,1080))
	checks["source_disables_gravel"]=not world.gravel_visual.visible
	var color_difference := 0.0
	for y in range(300,600,30):
		for x in range(400,900,30):
			var a: Color = cinematic.get_pixel(x,y); var b: Color = observed.get_pixel(x,y)
			color_difference+=absf(a.r-b.r)+absf(a.b-b.b)
	checks["source_and_cinematic_render_differ"]=color_difference>0.1
	checks["appearance_keeps_collision"]=world.terrain_root.get_child(0).get_child(1).shape.get_instance_id()==shape_id
	world.set_source_appearance(false)
	sun(world,Vector3(-0.8,0.12,0.5))
	await shot("bradbury_low_sun",Vector2i(1920,1080))
	sun(world,Vector3(-0.8,-0.35,0.5))
	var night: Image = await shot("bradbury_night",Vector2i(1920,1080))
	var night_light := 0.0
	for y in range(550,700,30):
		for x in range(500,900,30):
			var color: Color = night.get_pixel(x,y)
			night_light+=maxf(color.r,maxf(color.g,color.b))
	checks["night_has_no_ambient_fill"]=night_light<0.05
	current_camera.queue_free()
	world.orbit.camera.current=true
	sun(world,Vector3(-0.4,0.75,-0.3))
	var initial: Vector3 = world.rover.chassis.position
	Input.action_press("forward")
	await create_timer(1).timeout
	Input.action_release("forward")
	checks["drive_with_detail"]=world.rover.chassis.position.distance_to(initial)>0.01
	world.overhead.position=Vector3(0,500,0)
	world.overhead.look_at(Vector3.ZERO,Vector3.FORWARD); world.overhead.current=true
	await shot("bradbury_overhead",Vector2i(1600,900))
	measurements["detail_final"]=world.detail.metrics.duplicate()
	globe=await return_globe(world)
	globe.patch_builder.evaluator.artifacts.root_path="user://detail_visual_verification/"
	globe.drive_bradbury()
	world=await patch(globe)
	checks["repeat_deployment"]=world!=null and world.result.disk_hits.has("shading")
	if world==null: quit(1); return
	measurements["warm_build_ms"]=world.result.build_ms
	globe=await return_globe(world)
	for target in [{"name":"jezero","point":Vector2(18.44,77.45)},{"name":"mola","point":Vector2(0,179.999)}]:
		var point: Vector2 = target.point
		var cell := {"id":target.name,"bounds":Rect2(point.y-0.0078125,point.x-0.0078125,0.015625,0.015625)}
		globe.prepare_patch(TerrainMissionRegion.from_cell(cell,globe.surface_service))
		world=await patch(globe)
		checks[target.name+"_cell_deployment"]=world!=null
		if world==null: quit(1); return
		checks[target.name+"_source_fallback"]=world.result.sources.has("MOLA 64 ppd")
		await wait_detail(world)
		for size in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]: await shot(target.name+"_rover",size)
		measurements[target.name]=await measure(world,1.0,true)
		show_surface(world)
		await shot(target.name+"_close",Vector2i(1600,900))
		world.set_source_appearance(true)
		await shot(target.name+"_source",Vector2i(1600,900))
		globe=await return_globe(world)
	FileAccess.open("res://evidence/detail_visual_checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"measurements":measurements},"  "))
	print(JSON.stringify({"checks":checks,"measurements":measurements}))
	globe.queue_free()
	await process_frame
	await process_frame
	quit(1 if checks.values().has(false) else 0)
