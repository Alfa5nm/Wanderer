extends SceneTree

var checks: Dictionary = {}
var measurements: Dictionary = {}

class FlatFixture extends TerrainHeightField:
	var invalid := false
	func sample(x: float,z: float) -> Dictionary:
		return {"height":0.0,"valid":not invalid,"spacing_m":1.0,"source":"test fixture","geo":Vector2(x,z)}
	func normal(_x: float,_z: float,_step: float=0) -> Vector3: return Vector3.UP

func _initialize() -> void: call_deferred("run")

func wait(seconds: float) -> void: await create_timer(seconds,true,false,true).timeout

func run() -> void:
	var fixture := FlatFixture.new(); fixture.region=TerrainMissionRegion.new(); fixture.region.size_m=Vector2(24,24)
	var rock := {"position":Vector3.ZERO,"size":0.8,"shape":Vector3.ONE}
	var request := {"field":fixture,"start":Vector2(-8,0),"goal":Vector2(8,0),"rocks":[rock],"generation":1}
	var detour := ScoutRoutePlanner.plan(request)
	checks["astar_detours_obstacle"]=detour.points.size()>2 and detour.state=="revised proposal"
	var clear := true
	for point in detour.points: clear=clear and point.length()>=1.8
	checks["clearance_validated"]=clear
	fixture.invalid=true
	checks["invalid_coverage_no_route"]=ScoutRoutePlanner.plan(request).state=="no route found"
	var world: Node = load("res://procedural_terrain/mission.tscn").instantiate()
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+180000
	while not world.initialized_patch and Time.get_ticks_msec()<deadline: await process_frame
	if not world.initialized_patch: quit(1); return
	await wait(1.0)
	var actor: MarsAstronaut = world.astronaut
	print("ASTRONAUT_DIAGNOSTIC ",actor.animation.get_animation_list()," bones ",actor.skeleton.get_bone_count()," at ",actor.position)
	checks["required_bones"]=actor.skeleton.find_bone("foot.L")>=0 and actor.skeleton.find_bone("toe.R")>=0 and actor.skeleton.find_bone("head")>=0
	checks["ten_animation_clips"]=actor.animation.get_animation_list().size()>=10
	checks["physical_bones_bound"]=actor.physical_bones.all(func(bone): return bone.get_bone_id()>=0)
	var grounded_samples := 0
	for i in 30:
		await physics_frame
		if actor.is_on_floor(): grounded_samples+=1
	checks["idle_grounded"]=grounded_samples>=20
	var collision_hash: String = world.result.hashes.collision
	var human_key := InputEventKey.new(); human_key.keycode=KEY_H; human_key.pressed=true
	root.push_input(human_key,true)
	await process_frame
	checks["keyboard_h_switch"]=world.human_control
	checks["human_time_1x_120hz"]=Engine.time_scale==1 and Engine.physics_ticks_per_second==120
	var joy := InputEventJoypadMotion.new(); joy.axis=JOY_AXIS_LEFT_Y; joy.axis_value=-1
	root.push_input(joy,true)
	await wait(0.5)
	checks["injected_left_stick_moves"]=Vector2(actor.velocity.x,actor.velocity.z).length()>0.2
	joy.axis_value=0; root.push_input(joy,true)
	var orbit_yaw: float = actor.camera_rig.yaw
	joy.axis=JOY_AXIS_RIGHT_X; joy.axis_value=0.5; root.push_input(joy,true)
	await wait(0.2); joy.axis_value=0; root.push_input(joy,true)
	checks["injected_right_stick_camera"]=absf(actor.camera_rig.yaw-orbit_yaw)>0.01
	var from: Vector3 = actor.position
	Input.action_press("forward")
	await wait(2.0)
	Input.action_release("forward")
	checks["human_walks"]=actor.position.distance_to(from)>0.8
	checks["speed_limit"]=Vector2(actor.velocity.x,actor.velocity.z).length()<=1.02
	await wait(0.5)
	checks["stops_and_grounded"]=Vector2(actor.velocity.x,actor.velocity.z).length()<0.04 and actor.is_on_floor()
	checks["pelvis_bounded"]=absf(actor.pelvis_offset)<=0.151
	actor.fall(); await wait(0.8)
	checks["ragdoll_active"]=actor.simulator.active and actor.state=="fallen"
	checks["ragdoll_finite"]=actor.physical_bones.all(func(bone): return bone.global_position.is_finite())
	checks["safe_recovery"]=actor.recover()
	await wait(0.2)
	var switch_pad := InputEventJoypadButton.new(); switch_pad.button_index=JOY_BUTTON_DPAD_UP; switch_pad.pressed=true
	root.push_input(switch_pad,true)
	checks["gamepad_switch"]=not world.human_control
	checks["rover_pace_restored"]=Engine.time_scale==6 and Engine.physics_ticks_per_second==720
	world.scout.propose(Vector2(-5,0),Vector2(5,0))
	checks["proposal_unverified"]=world.scout.session.route.state=="unverified proposal"
	world.scout.replan()
	deadline=Time.get_ticks_msec()+30000
	while (world.scout.worker!=null or world.scout.pending) and Time.get_ticks_msec()<deadline: await process_frame
	checks["replan_completes"]=not world.scout.pending and world.scout.worker==null and world.scout.session.route.state in ["revised proposal","no route found"]
	measurements["planner_ms"]=world.scout.last_plan_ms
	checks["geometry_collision_unchanged"]=collision_hash==world.result.hashes.collision
	var session: ScoutSession = world.scout.session
	session.record({"kind":"simulated_obstacle","latitude":-4.5895,"longitude":137.4417,"description":"test session record","source":"fixture","spacing_m":0,"region":"test"})
	checks["session_deduplicates"]=not session.record({"kind":"simulated_obstacle","latitude":-4.5895,"longitude":137.4417})
	checks["science_positions_verified"]=PlanetScienceSite.curated().size()==2
	measurements["ik"]=actor.metrics.duplicate()
	FileAccess.open("res://evidence/astronaut_scout_checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"measurements":measurements},"  "))
	print(JSON.stringify({"checks":checks,"measurements":measurements}))
	Engine.time_scale=1; Engine.physics_ticks_per_second=120
	world.queue_free(); await process_frame; await process_frame
	checks["session_survives_scene"]=is_instance_valid(session) and not session.findings.is_empty()
	FileAccess.open("res://evidence/astronaut_scout_checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"measurements":measurements},"  "))
	quit(1 if checks.values().has(false) else 0)
