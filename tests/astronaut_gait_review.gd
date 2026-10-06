extends "res://tests/scout_capture.gd"
func run() -> void:
	root.mode=Window.MODE_WINDOWED; root.size=Vector2i(1600,900); root.content_scale_size=root.size
	var world: Node = load("res://procedural_terrain/mission.tscn").instantiate()
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+180000
	while not world.initialized_patch and Time.get_ticks_msec()<deadline: await process_frame
	if not world.initialized_patch: quit(1); return
	world.scout.enabled=false; world.set_sun_direction(Vector3(-0.35,0.7,-0.4))
	world.switch_actor(); world.recording.show_hud(false)
	var actor: MarsAstronaut = world.astronaut
	actor.camera_rig.yaw=0; actor.camera_rig.enabled=false
	var camera := Camera3D.new(); world.add_child(camera); camera.fov=46; camera.current=true
	await wall(0.5)
	var hands := [INF,-INF,INF,-INF]
	var highest := 0.0; var lowest_knee_forward := INF
	var crossed := false
	var frames: Array = []
	Input.action_press("forward"); await wall(1.0)
	var began := Time.get_ticks_msec(); var next_shot := 0.0
	while Time.get_ticks_msec()-began<5000:
		camera.position=actor.position+Vector3(3.8,1.4,0.4); camera.look_at(actor.position+Vector3.UP*0.95)
		await process_frame
		var data := {"phase":actor.phase,"left_planted":actor.feet[0].planted,"right_planted":actor.feet[1].planted}
		for i in 2:
			var side: String = "L" if i==0 else "R"
			var hand: Vector3 = (actor.skeleton.global_transform*actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("hand."+side))).origin
			var local: Vector3 = actor.global_transform.affine_inverse()*hand
			hands[i*2]=minf(hands[i*2],local.z); hands[i*2+1]=maxf(hands[i*2+1],local.z)
			var foot: Vector3 = (actor.skeleton.global_transform*actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("foot."+side))).origin
			var hit: Dictionary = actor.support(foot)
			if not hit.is_empty(): highest=maxf(highest,foot.y-hit.position.y)
			var knee: Vector3 = (actor.skeleton.global_transform*actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("shin."+side))).origin
			var hip: Vector3 = (actor.skeleton.global_transform*actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("thigh."+side))).origin
			var leg_line := foot-hip
			var fraction := (knee-hip).dot(leg_line)/maxf(leg_line.length_squared(),0.0001)
			var bend := knee-(hip+leg_line*fraction)
			lowest_knee_forward=minf(lowest_knee_forward,bend.dot(actor.global_basis.z))
			var knee_local: Vector3 = actor.global_transform.affine_inverse()*knee
			crossed=crossed or (knee_local.x<0 if i==0 else knee_local.x>0)
			data["hand_"+side]=local.z; data["foot_"+side]=foot.y-(hit.position.y if not hit.is_empty() else foot.y)
		frames.append(data)
		var elapsed := float(Time.get_ticks_msec()-began)/1000
		if elapsed>=next_shot and next_shot<1.0:
			await shot("gait_side_%d" % roundi(next_shot*4),Vector2i(1600,900)); next_shot+=0.25
	var old_phase: float = actor.animation.current_animation_position/actor.animation.current_animation_length
	actor.play_clip("fast_walk")
	checks["walk_fast_cycle_preserved"]=absf(actor.animation.current_animation_position/actor.animation.current_animation_length-old_phase)<0.01
	actor.play_clip("walk")
	actor.camera_rig.yaw=PI/2
	await wall(0.25)
	checks["turn_keeps_walking_clip"]=actor.state=="walk"
	Input.action_release("forward"); await wall(0.4)
	checks["both_arms_swing"]=hands[1]-hands[0]>0.20 and hands[3]-hands[2]>0.20
	checks["swing_foot_lifts"]=highest>0.155
	checks["knees_stay_in_own_lanes"]=not crossed
	checks["knees_bend_forward"]=lowest_knee_forward>0.0
	checks["planted_target_stable"]=actor.metrics.planted_drift_m<0.05
	measurements={"hand_z_ranges":hands,"max_ankle_ground_clearance_m":highest,"minimum_knee_forward_m":lowest_knee_forward,"ik":actor.metrics,"samples":frames}
	FileAccess.open("res://evidence/astronaut_gait_review.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"measurements":measurements},"  "))
	print(JSON.stringify({"checks":checks,"hand_z_ranges":hands,"clearance":highest,"knee_forward":lowest_knee_forward,"ik":actor.metrics}))
	Engine.time_scale=1; Engine.physics_ticks_per_second=120; world.queue_free(); await process_frame; await process_frame
	quit(1 if checks.values().has(false) else 0)
