extends SceneTree

var globe: Node3D

func _initialize() -> void:
	call_deferred("run")

func wait_focus() -> void:
	for i in 80:
		await create_timer(0.1,true,false,true).timeout
		if not globe.rig.focusing: break
	print("FOCUS ",globe.state," ",globe.rig.distance," ",globe.rig.focusing)

func run() -> void:
	globe=load("res://planetary_map/mars_globe.tscn").instantiate()
	root.add_child(globe)
	current_scene=globe
	root.borderless=true
	root.size=Vector2i(1920,1080)
	globe.rig.locked=true
	await create_timer(0.2,true,false,true).timeout
	globe.select_marker(globe.mission)
	await wait_focus()
	globe.explore_mission()
	await wait_focus()
	var original: float=globe.surface_service.sample(-4.5895,137.4417).offset_m
	globe.rig.locked=false
	for i in 240:
		await create_timer(0.25,true,false,true).timeout
		if globe.streamer.completed.size()>=2 and globe.terrain.pending.is_empty() and globe.terrain.worker==null: break
	globe.rig.locked=true
	var checks := {"offline":globe.streamer.offline,"automatic_bundled_tiles":globe.streamer.completed.size()>=2,"no_external_worker":globe.streamer.pid<0,"refinement_settled":globe.terrain.pending.is_empty() and globe.terrain.worker==null,"source_sample_preserved":absf(globe.surface_service.sample(-4.5895,137.4417).offset_m-original)<0.1}
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/cosmoscope_bradbury.png")
	FileAccess.open("res://evidence/cosmoscope_render_checks.json",FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
	print(JSON.stringify(checks))
	await create_timer(1.0,true,false,true).timeout
	globe.queue_free()
	await process_frame
	await process_frame
	quit(1 if checks.values().has(false) else 0)
