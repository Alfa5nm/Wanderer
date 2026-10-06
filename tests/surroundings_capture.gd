extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var globe = load("res://planetary_map/mars_globe.tscn").instantiate()
	root.add_child(globe)
	current_scene=globe
	root.size=Vector2i(1920,1080)
	globe.rig.locked=true
	globe.streamer.cache_root="user://surroundings_verification/"
	globe.streamer.status_changed.connect(func(message): print("STREAM ",message))
	await create_timer(0.3).timeout
	globe.select_marker(globe.find_marker("perseverance"))
	globe.rig.focus_on_coordinates(18.44,77.45,1.03092)
	for i in 100:
		await create_timer(0.1).timeout
		if not globe.rig.focusing: break
	globe.rig.locked=false
	var started := Time.get_ticks_msec()
	var loaded := false
	for i in 120:
		await create_timer(0.25).timeout
		for data in globe.surface_service.datasets:
			if data.metadata.get("role","")=="view_background": loaded=true
		if loaded:
			await create_timer(1.0).timeout
			break
	globe.rig.locked=true
	var checks := {"automatic_visible_area_loaded":loaded,"load_seconds":float(Time.get_ticks_msec()-started)/1000,"view_bounds":str(globe.streamer.surrounding_rectangles)}
	for data in globe.surface_service.datasets:
		if data.metadata.get("role","")=="view_background":
			checks["valid_fraction"]=data.metadata.valid_fraction
			checks["spacing_m"]=data.prepared_spacing_m
			checks["source_tiles"]=data.metadata.source_tiles.size()
	for resolution in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]:
		root.size=resolution
		await create_timer(1).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/jezero_surroundings_%dx%d.png" % [resolution.x,resolution.y])
	FileAccess.open("res://evidence/jezero_surroundings_checks.json",FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
	print(JSON.stringify(checks))
	globe.queue_free()
	await process_frame
	await process_frame
	quit(0 if loaded else 1)
