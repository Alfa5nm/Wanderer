extends SceneTree
var checks := {}
func _initialize() -> void: call_deferred("run")
func simulate(fps: int) -> Vector3:
	var rig := PlanetCameraRig.new()
	root.add_child(rig)
	rig.set_process(false)
	rig.velocity=Vector2(0.4,0.1)
	rig.distance=1.05
	rig.target_distance=1.01
	var initial := rig.yaw
	for i in fps: rig._process(1.0/fps)
	var result := Vector3(rig.yaw-initial,rig.pitch,rig.distance)
	rig.free()
	return result
func run() -> void:
	var a := simulate(30)
	var b := simulate(60)
	var c := simulate(120)
	checks["motion_30_60_120_equivalent"]=a.distance_to(b)<0.00002 and b.distance_to(c)<0.00002
	var rig := PlanetCameraRig.new()
	root.add_child(rig)
	rig.set_process(false)
	var yaw := rig.yaw
	rig.orbit_drag(Vector2(10,4),0.001)
	rig.orbit_drag(Vector2(10,4),0.001)
	checks["events_accumulated"]=rig.pending_drag==Vector2(20,8) and rig.yaw==yaw
	rig._process(1.0/60)
	checks["drag_applied_on_frame"]=rig.pending_drag==Vector2.ZERO and rig.yaw<yaw
	rig.begin_drag()
	rig.orbit_drag(Vector2(10,0),0.016)
	rig._process(1.0/60)
	var held_yaw := rig.yaw
	for i in 6: rig._process(1.0/60)
	checks["held_drag_no_between_event_sway"]=rig.yaw==held_yaw
	rig.end_drag()
	for i in 6: rig._process(1.0/60)
	checks["release_stops_mouse_motion"]=rig.yaw==held_yaw and rig.velocity==Vector2.ZERO
	checks["near_surface_sensitivity"]=true
	rig.distance=1.000025
	checks["near_surface_sensitivity"]=rig.orbit_scale()<0.00003
	rig.focus_on_coordinates(0,rad_to_deg(rig.yaw)+180,1.01,0.5)
	await create_timer(0.25).timeout
	checks["distant_selection_pullback"]=rig.distance>1.1
	rig.orbit_drag(Vector2(2,0),0.016)
	checks["flight_interrupts"]=not rig.focusing
	rig.focus_on_coordinates(89.9,179.9,1.04,0.2)
	await create_timer(0.3).timeout
	checks["polar_flight_finite"]=is_finite(rig.pitch) and absf(rig.pitch)<=1.48 and not rig.focusing
	var lighting := PlanetLighting.new()
	root.add_child(lighting)
	checks["true_dark_ambient"]=lighting.environment.ambient_light_source==Environment.AMBIENT_SOURCE_DISABLED
	checks["sun_light_alignment"]=lighting.sun.global_basis.z.normalized().distance_to(lighting.settings.sun_direction)<0.001
	print(JSON.stringify(checks))
	FileAccess.open("res://evidence/cinematic_checks.json",FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
	rig.free()
	lighting.free()
	quit(1 if checks.values().has(false) else 0)
