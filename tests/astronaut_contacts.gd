extends SceneTree
var checks := {}
func _initialize() -> void: call_deferred("run")
func wait(seconds: float) -> void: await create_timer(seconds,true,false,true).timeout
func box(parent: Node,point: Vector3,size: Vector3,angle: float=0) -> StaticBody3D:
	var body := StaticBody3D.new(); body.position=point; body.rotation.x=angle; body.collision_layer=1
	var shape := CollisionShape3D.new(); var geometry := BoxShape3D.new(); geometry.size=size; shape.shape=geometry
	body.add_child(shape); parent.add_child(body); return body
func run() -> void:
	Engine.time_scale=1; Engine.physics_ticks_per_second=120
	for action in ["forward","reverse","left","right","brake","camera_reset","reset_rover"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	var scene := Node3D.new(); root.add_child(scene); current_scene=scene
	box(scene,Vector3(0,-0.25,0),Vector3(30,0.5,30))
	box(scene,Vector3(0,0.10,3),Vector3(4,0.20,2))
	var actor := MarsAstronaut.new(); actor.position=Vector3(0,0.03,0); actor.controlled=true; scene.add_child(actor)
	await wait(0.6); actor.camera_rig.yaw=0
	checks["idle_flat_ground"]=actor.is_on_floor()
	Input.action_press("forward"); await wait(3.6); Input.action_release("forward")
	print("STEP_DIAGNOSTIC ",actor.position," grounded ",actor.is_on_floor())
	checks["steps_20cm"]=actor.position.z>3 and actor.position.y>0.15 and actor.is_on_floor()
	await wait(0.4)
	checks["stop_on_step"]=actor.velocity.length()<0.2
	checks["planted_lock_under_5cm"]=actor.metrics.planted_drift_m<0.05
	checks["ik_endpoint_under_1cm"]=actor.metrics.solver_error_m<0.01
	checks["pelvis_reach_limit"]=absf(actor.pelvis_offset)<=0.15
	box(scene,Vector3(0,0.6,8),Vector3(4,0.2,4),deg_to_rad(-20))
	actor.respawn(Vector3(0,0.03,5)); await wait(0.3)
	Input.action_press("forward"); await wait(4.0); Input.action_release("forward")
	checks["walks_20deg_ramp"]=actor.position.z>7 and actor.position.y>0.25
	actor.fall(); await wait(0.4)
	var blocker := box(scene,actor.last_floor+Vector3.UP,Vector3(1,2,1))
	await physics_frame
	checks["blocked_recovery_rejected"]=not actor.recover()
	blocker.queue_free(); await physics_frame; await physics_frame
	checks["clear_recovery_allowed"]=actor.recover()
	var report := {"checks":checks,"contact_metrics":actor.metrics,"position":str(actor.position)}
	FileAccess.open("res://evidence/astronaut_contacts.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report)); scene.queue_free(); await process_frame; await process_frame
	quit(1 if checks.values().has(false) else 0)
