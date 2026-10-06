extends SceneTree

var checks: Dictionary = {}
var globe: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(id: String, result: bool) -> void:
	checks[id] = result
	if not result: push_error("FAIL: " + id)

func wait(seconds: float) -> void:
	await create_timer(seconds,true,false,true).timeout

func inject(event: InputEvent) -> void:
	Input.parse_input_event(event.duplicate())
	Input.flush_buffered_events()

func button(index: int, down: bool, point: Vector2, twice: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = down
	event.position = point
	event.double_click = twice
	root.push_input(event, true)

func boot() -> void:
	globe = load("res://planetary_map/mars_globe.tscn").instantiate()
	root.add_child(globe)
	current_scene = globe
	await wait(0.1)

func run() -> void:
	check("axes_north",PlanetCoordinates.lat_lon_to_local(90,0).distance_to(Vector3.UP)<0.00001)
	check("axes_zero",PlanetCoordinates.lat_lon_to_local(0,0).distance_to(Vector3.BACK)<0.00001)
	check("axes_east",PlanetCoordinates.lat_lon_to_local(0,90).distance_to(Vector3.RIGHT)<0.00001)
	var good := true
	for lat in [-90,-80,-4.5895,0,60,90]:
		for lon in [-180,-90,0,137.4417,180,540]:
			var p := PlanetCoordinates.lat_lon_to_local(lat,lon,2.0,0.1)
			var ll := PlanetCoordinates.local_to_lat_lon(p)
			good = good and absf(ll.x-lat)<0.001 and absf(p.length()-2.1)<0.0001
			if absf(lat)<89: good = good and absf(wrapf(ll.y-lon,-180,180))<0.001
	check("roundtrip_poles_wrap_altitude",good)
	var transform := Transform3D(Basis(Vector3.RIGHT,0.5).scaled(Vector3(2,3,4)),Vector3(3,8,-4))
	var world := PlanetCoordinates.lat_lon_to_world(-4.5895,137.4417,1,0.1,transform)
	var ll := PlanetCoordinates.world_to_lat_lon(world,transform)
	check("transformed_planet",ll.distance_to(Vector2(-4.5895,137.4417))<0.001)
	check("invalid_rejected",not PlanetCoordinates.valid(91,0) and not PlanetCoordinates.valid(0,INF) and is_inf(PlanetCoordinates.local_to_lat_lon(Vector3.ZERO).x))
	check("uv_cardinals",PlanetCoordinates.lat_lon_to_uv(0,0)==Vector2(0.5,0.5) and PlanetCoordinates.lat_lon_to_uv(90,-180)==Vector2.ZERO)
	check("occlusion_front",PlanetMarkerManager.front_visible(Vector3.BACK,Vector3.ZERO,Vector3(0,0,3)))
	check("occlusion_back",not PlanetMarkerManager.front_visible(Vector3.FORWARD,Vector3.ZERO,Vector3(0,0,3)))
	check("ray_intersection",PlanetCoordinates.surface_hit(Vector3(0,0,3),Vector3.FORWARD,1).distance_to(Vector3.BACK)<0.0001)
	var alternate_rig := PlanetCameraRig.new()
	alternate_rig.radius = 2.0
	root.add_child(alternate_rig)
	alternate_rig.focus_on_coordinates(0,0,1.85,0.01)
	check("normalized_planet_radius",alternate_rig.target_distance == 3.7 and alternate_rig.min_distance == 2.07)
	alternate_rig.queue_free()
	var route := PlanetRoute.new()
	for i in 3:
		var point := PlanetWaypoint.new()
		point.latitude = i
		point.longitude = 179+i
		point.sol = i
		point.date = "2012-08-%02d" % (6+i)
		route.waypoints.append(point)
	check("timeline_sol",route.points_until(1).size()==2)
	check("timeline_date",route.points_until(-1,"2012-08-06").size()==1)
	var renderer := PlanetRouteRenderer.new()
	root.add_child(renderer)
	renderer.route = route
	renderer.rebuild()
	check("route_projection",renderer.mesh != null)
	route.development_only = true
	renderer.rebuild()
	check("development_route_hidden",renderer.mesh == null)
	renderer.queue_free()
	await boot()
	check("resource_content",globe.definition.markers.size()==12 and globe.definition.markers.filter(func(m): return m is PlanetScienceSite).size()==2 and globe.mission.latitude == -4.5895 and globe.mission.landing_date == "2012-08-06")
	check("boot_state",globe.state == globe.Navigation.PLANET_VIEW and globe.history.is_empty())
	check("visual_texture",globe.surface.material_override.albedo_texture != null and globe.layer_manager.available_layers()==["visual"])
	var bad_layer := PlanetDataLayer.new()
	bad_layer.id = "missing"
	bad_layer.texture_path = "res://missing_texture.jpg"
	globe.layer_manager.register_layer(bad_layer)
	check("texture_fallback",globe.layer_manager.set_view_mode("missing") and globe.surface.material_override.albedo_texture == null)
	globe.layer_manager.set_view_mode("visual")
	check("unavailable_layer_absent",not globe.layer_manager.available_layers().has("missing"))
	var missing_route := PlanetMission.new()
	missing_route.route_file = "res://missing_route.tres"
	check("missing_route_safe",missing_route.resolved_route() == null)
	var invalid_marker := PlanetMarkerData.new()
	invalid_marker.id = "bad"
	invalid_marker.latitude = 100
	globe.select_marker(invalid_marker)
	check("invalid_marker_safe",globe.state == globe.Navigation.PLANET_VIEW)
	var yaw: float = globe.rig.yaw
	button(MOUSE_BUTTON_LEFT,true,Vector2(600,300))
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(660,320)
	motion.relative = Vector2(60,20)
	inject(motion)
	button(MOUSE_BUTTON_LEFT,false,Vector2(660,320))
	await wait(0.05)
	check("mouse_drag",absf(globe.rig.yaw-yaw)>0.1)
	var distance: float = globe.rig.target_distance
	button(MOUSE_BUTTON_WHEEL_UP,true,Vector2(600,300))
	check("wheel_zoom",globe.rig.target_distance<distance)
	for i in 100: globe.rig.zoom(-1)
	check("minimum_zoom",globe.rig.target_distance==globe.rig.min_distance)
	for i in 100: globe.rig.zoom(1)
	check("maximum_zoom",globe.rig.target_distance==globe.rig.max_distance)
	globe.rig.velocity = Vector2.ZERO
	globe.rig.yaw = deg_to_rad(120)
	globe.rig.pitch = deg_to_rad(12)
	globe.rig.distance = 3.4
	globe.rig.target_distance = 3.4
	globe.rig.update_camera()
	globe.refresh()
	var anchor: Vector2 = globe.markers.anchor("curiosity")
	button(MOUSE_BUTTON_LEFT,true,anchor+Vector2(12,0))
	await process_frame
	button(MOUSE_BUTTON_LEFT,false,anchor+Vector2(12,0))
	check("enlarged_click_selects",globe.state == globe.Navigation.REGION_FOCUS and globe.selected_id == "curiosity")
	globe.refresh()
	anchor = globe.markers.anchor("curiosity")
	button(MOUSE_BUTTON_LEFT,true,anchor,true)
	button(MOUSE_BUTTON_LEFT,false,anchor)
	check("double_click_focus",globe.rig.focusing and globe.state == globe.Navigation.REGION_FOCUS)
	await wait(3.0)
	check("focus_gale",absf(rad_to_deg(globe.rig.pitch)+4.5)<0.01 and absf(rad_to_deg(globe.rig.yaw)-137.4)<0.01)
	check("context_panel",globe.hud.panel.visible and globe.hud.panel.deploy.visible)
	globe.hud.panel.explore.pressed.emit()
	await wait(2.0)
	check("explore_bradbury",globe.state == globe.Navigation.MISSION_FOCUS and globe.selected_id == "bradbury")
	var back := InputEventKey.new()
	back.keycode = KEY_ESCAPE
	back.pressed = true
	inject(back)
	check("back_region",globe.state == globe.Navigation.REGION_FOCUS)
	inject(back)
	check("back_planet",globe.state == globe.Navigation.PLANET_VIEW and not globe.hud.panel.visible)
	await wait(0.9)
	# Focus can be interrupted by wheel input, without an obsolete tween restoring it.
	globe.rig.focus_on_coordinates(0,170,1.4,1.0)
	globe.rig.zoom(1)
	check("focus_interrupt",not globe.rig.focusing)
	globe.rig.test_pad = 0
	var axis := InputEventJoypadMotion.new()
	axis.device = 0
	axis.axis = JOY_AXIS_LEFT_X
	axis.axis_value = 0.8
	inject(axis)
	globe.rig.focus_on_coordinates(0,170,1.4,1.0)
	yaw = globe.rig.yaw
	await wait(0.3)
	check("controller_focus_interrupt",not globe.rig.focusing)
	check("controller_orbit",globe.rig.yaw<yaw)
	axis.axis_value = 0
	inject(axis)
	axis.axis = JOY_AXIS_TRIGGER_RIGHT
	axis.axis_value = 1
	inject(axis)
	distance = globe.rig.target_distance
	await wait(0.2)
	check("controller_zoom",globe.rig.target_distance<distance)
	axis.axis_value = 0
	inject(axis)
	globe.rig.test_pad = -1
	globe.rig.focus_on_coordinates(-4.5895,137.4417,3.4,0.1)
	await wait(0.2)
	globe.refresh()
	var confirm := InputEventJoypadButton.new()
	confirm.device = 0
	confirm.button_index = JOY_BUTTON_A
	confirm.pressed = true
	inject(confirm)
	check("controller_select",globe.state == globe.Navigation.REGION_FOCUS)
	axis.axis = JOY_AXIS_LEFT_Y
	axis.axis_value = 0.8
	inject(axis)
	await process_frame
	check("orbit_axis_preserves_ui_focus",globe.hud.panel.explore.has_focus())
	axis.axis_value = 0
	inject(axis)
	confirm.button_index = JOY_BUTTON_B
	inject(confirm)
	check("controller_back",globe.state == globe.Navigation.PLANET_VIEW)
	globe.select_marker(globe.mission)
	var scene_path: String = globe.region.deployment_scene
	globe.region.deployment_scene = "res://missing_gameplay.tscn"
	globe.deploy()
	check("missing_scene_retry",not globe.deployment.active and globe.hud.panel.visible and not globe.hud.notice.text.is_empty())
	globe.region.deployment_scene = scene_path
	globe.deploy()
	await wait(0.2)
	globe.go_back()
	check("cancel_descent",not globe.deployment.active and not globe.rig.locked and globe.selection.enabled)
	globe.deploy()
	await wait(6.0)
	check("deploy_existing_scene",not is_instance_valid(globe) and current_scene.scene_file_path == "res://main.tscn")
	if is_instance_valid(globe):
		print(JSON.stringify(checks))
		quit(1)
		return
	check("existing_rover_ready",current_scene.rover != null and current_scene.orbit.target == current_scene.rover.chassis)
	check("gameplay_time_restored",Engine.time_scale == 6.0 and Engine.physics_ticks_per_second == 720)
	var throttle := InputEventKey.new()
	throttle.keycode = KEY_W
	throttle.physical_keycode = KEY_W
	throttle.pressed = true
	inject(throttle)
	await wait(0.05)
	check("rover_drive_after_deploy",current_scene.rover.command_v>0)
	throttle.pressed = false
	inject(throttle)
	current_scene.queue_free()
	await process_frame
	await boot()
	check("reboot_time_reset",Engine.time_scale == 1.0 and Engine.physics_ticks_per_second == 120)
	globe.select_marker(globe.mission)
	globe.deploy()
	await wait(6.0)
	check("repeat_deploy",current_scene.scene_file_path == "res://main.tscn")
	FileAccess.open("res://evidence/globe_checks.json",FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
	print(JSON.stringify(checks))
	var failed := checks.values().has(false)
	# Let the wall-time reveal release its resources before test-process shutdown.
	await wait(1.0)
	current_scene.queue_free()
	await process_frame
	await process_frame
	quit(1 if failed else 0)
