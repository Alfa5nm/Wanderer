extends SceneTree

var globe: Node3D
func _initialize() -> void:
	call_deferred("run")

func pause(seconds: float) -> void:
	await create_timer(seconds,true,false,true).timeout

func settle() -> void:
	for i in 160:
		await pause(0.25)
		if globe.terrain.pending.is_empty() and globe.terrain.worker==null: return

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/"+name+".png")

func run() -> void:
	globe=load("res://planetary_map/mars_globe.tscn").instantiate()
	root.add_child(globe)
	current_scene=globe
	globe.rig.locked=true
	root.borderless=true
	root.size=Vector2i(1920,1080)
	root.position=Vector2i.ZERO
	print("DEVICES ",Input.get_connected_joypads())
	await settle()
	await capture("terrain_orbit_direct")
	globe.rig.focus_on_coordinates(-4.5,137.4,1.3)
	await globe.rig.focus_finished
	await settle()
	await capture("terrain_low_orbit_direct")
	globe.select_marker(globe.mission)
	await globe.rig.focus_finished
	await settle()
	print("GALE ",globe.rig.snapshot()," ",globe.rig.distance," ",globe.rig.focusing)
	await capture("terrain_gale_direct")
	globe.explore_mission()
	await globe.rig.focus_finished
	await settle()
	print("BRADBURY ",globe.rig.snapshot()," ",globe.rig.distance," ",globe.rig.focusing)
	await capture("terrain_local_direct")
	globe.grid_toggle.button_pressed=true
	await pause(0.6)
	await capture("terrain_grid_direct")
	globe.queue_free()
	await process_frame
	quit()
