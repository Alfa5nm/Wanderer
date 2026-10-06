extends SceneTree
var globe: Node3D
var report := {}
func _initialize() -> void: call_deferred("run")
func capture(label: String) -> void:
	if root.mode==Window.MODE_MINIMIZED: root.mode=Window.MODE_WINDOWED
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/cinematic_"+label+".png")
func run() -> void:
	globe=load("res://planetary_map/mars_globe.tscn").instantiate()
	root.add_child(globe)
	current_scene=globe
	root.size=Vector2i(1920,1080)
	globe.rig.locked=true
	globe.selection.enabled=false
	root.gui_disable_input=true
	await create_timer(2).timeout
	var started := Time.get_ticks_msec()
	var roots_ready := false
	while Time.get_ticks_msec()-started<20000:
		roots_ready=true
		for face in 6:
			if not globe.terrain.patches.has("%d/0/0/0" % face): roots_ready=false
		if roots_ready: break
		await process_frame
	report["six_coarse_faces_ready"]=roots_ready
	for spec in [["day",20.0,120.0],["terminator",0.0,45.0],["night",-20.0,-60.0]]:
		globe.rig.focus_on_coordinates(spec[1],spec[2],3.4,0.8)
		await create_timer(8).timeout
		await capture(spec[0])
		if spec[0]=="day":
			globe.terrain.atmosphere.hide()
			await create_timer(0.1).timeout
			await capture("day_no_atmosphere")
			globe.terrain.atmosphere.show()
	var times: Array[float]=[]
	for i in 120:
		var before := Time.get_ticks_usec()
		await process_frame
		times.append((Time.get_ticks_usec()-before)/1000.0)
	times.sort()
	report["orbital_frame_median_ms"]=times[60]
	report["orbital_frame_p95_ms"]=times[114]
	globe.terrain.atmosphere.hide()
	await create_timer(0.5).timeout
	times.clear()
	for i in 120:
		var before := Time.get_ticks_usec()
		await process_frame
		times.append((Time.get_ticks_usec()-before)/1000.0)
	times.sort()
	report["without_atmosphere_median_ms"]=times[60]
	report["without_atmosphere_p95_ms"]=times[114]
	globe.terrain.atmosphere.show()
	globe.rig.camera.look_at(globe.lighting.settings.sun_direction*1000.0,Vector3.UP)
	await create_timer(0.1).timeout
	await capture("sun_occluded")
	globe.rig.focus_on_coordinates(20.0,120.0,3.4,0.2)
	await create_timer(1).timeout
	globe.rig.camera.look_at(globe.lighting.settings.sun_direction*1000.0,Vector3.UP)
	await create_timer(1).timeout
	await capture("sun")
	globe.rig.focus_on_coordinates(18.44,77.45,1.03092,0.8)
	await create_timer(10).timeout
	for size in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]:
		root.size=size
		await create_timer(1).timeout
		await capture("jezero_%dx%d" % [size.x,size.y])
	globe.rig.focus_on_coordinates(-4.5895,137.4417,1.00065,0.8)
	await create_timer(10).timeout
	await capture("bradbury")
	report["ambient_disabled"]=globe.lighting.environment.ambient_light_source==Environment.AMBIENT_SOURCE_DISABLED
	report["sun_direction_shared"]=globe.sun.global_basis.z.normalized().distance_to(globe.lighting.settings.sun_direction)<0.001
	FileAccess.open("res://evidence/cinematic_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	globe.queue_free()
	await process_frame
	await process_frame
	quit()
