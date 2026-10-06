extends SceneTree

const Rover = preload("res://scripts/rover.gd")
var scene: Node3D
var rover: Node3D
var results: Array = []
var trace: FileAccess
var case_name := ""
var simtime := 0.0
var samples: Array = []

func _initialize() -> void:
	call_deferred("run")

func terrain(size: Vector3, pos: Vector3, rotation: Vector3=Vector3.ZERO, friction: float=.85) -> void:
	var b := StaticBody3D.new()
	b.position=pos; b.rotation=rotation
	var c := CollisionShape3D.new(); var s := BoxShape3D.new(); s.size=size; c.shape=s
	b.add_child(c)
	var material := PhysicsMaterial.new(); material.friction=friction; b.physics_material_override=material
	scene.add_child(b)

func setup(name_of_case: String, slope: float=0.0, cross: bool=false, friction: float=.85, hz: int=120, torque_factor: float=1.0, differential_factor: float=1.0) -> void:
	if is_instance_valid(scene):
		root.remove_child(scene); scene.queue_free()
		await process_frame
	Engine.time_scale=1.0
	Engine.physics_ticks_per_second=hz
	scene=Node3D.new(); root.add_child(scene)
	var basis := Basis(Vector3.FORWARD if cross else Vector3.RIGHT,deg_to_rad(slope))
	terrain(Vector3(1000,.4,1000),basis*Vector3(0,-.2,0),basis.get_euler(),friction)
	rover=Node3D.new(); rover.set_script(Rover)
	rover.visual_enabled=false; rover.spawn_basis=basis; rover.spawn_offset=basis*Vector3(0,.02,0)
	rover.torque_scale=torque_factor; rover.differential_scale=differential_factor
	scene.add_child(rover)
	case_name=name_of_case; simtime=0; samples=[]

func steps(seconds: float, collect: bool=true) -> void:
	var hz := Engine.physics_ticks_per_second
	for i in int(seconds*hz):
		await physics_frame
		simtime+=1.0/hz
		if i%12==0 and collect:
			var t: Dictionary=rover.telemetry(); t["time"]=simtime; t["case"]=case_name
			samples.append(t)
			trace.store_line(JSON.stringify(t))

func summary(extra: Dictionary={}) -> Dictionary:
	var r: Dictionary={"case":case_name,"final":rover.telemetry()}
	var speed:=0.0; var support:=0.0; var slip:=0.0; var differential:=0.0; var min_contacts:=6; var max_torque:=0.0
	var window:=0
	for t in samples:
		var contacts:=0
		for w in t.wheels:
			if w.contacts>0: contacts+=1
			max_torque=maxf(max_torque,absf(w.torque))
		min_contacts=mini(min_contacts,contacts)
		differential=maxf(differential,absf(t.differential_error_deg))
		if t.time>simtime-5:
			speed+=t.forward_speed; support+=t.support_n
			for w in t.wheels: slip+=absf(w.slip)/6
			window+=1
	r.merge({"mean_forward_speed_last5":speed/maxi(window,1),"mean_support_last5":support/maxi(window,1),"mean_abs_slip_last5":slip/maxi(window,1),"max_differential_error_deg":differential,"min_wheels_contact":min_contacts,"max_abs_torque":max_torque})
	r.merge(extra)
	results.append(r)
	print("MEASUREMENT ",JSON.stringify(r))
	return r

func run() -> void:
	if "--solver-only" in OS.get_cmdline_user_args():
		trace=FileAccess.open("res://evidence/solver_trace.jsonl",FileAccess.WRITE)
		await setup("solver_40_16")
		await steps(8,false);rover.command_v=.04;await steps(30)
		var r:=summary({"configured_velocity_steps":ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/velocity_steps"),"configured_position_steps":ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/position_steps")})
		var f:=FileAccess.open("res://evidence/solver_validation.json",FileAccess.WRITE);f.store_string(JSON.stringify(r,"  "));f.close();trace.close();quit();return
	trace=FileAccess.open("res://evidence/physics_trace.jsonl",FileAccess.WRITE)
	await setup("settling")
	await steps(12)
	summary()
	for hz in [120,240]:
		await setup("straight_%dHz"%hz,0,false,.85,hz)
		await steps(8,false)
		var start: Vector3=rover.chassis.position
		rover.command_v=.04
		await steps(30)
		summary({"distance_m":rover.chassis.position.distance_to(start),"elapsed_drive_s":30,"hz":hz})
	await setup("reverse")
	await steps(8,false); rover.command_v=-.04; await steps(20); summary()
	await setup("point_turn")
	await steps(8,false); rover.command_yaw=.025; await steps(65); summary()
	await setup("arc_turn")
	await steps(8,false); rover.command_v=.04; rover.command_yaw=.01; await steps(65); summary()
	await setup("obstacle_100mm")
	terrain(Vector3(.7,.1,.65),Vector3(1.06,.05,1.72))
	await steps(8,false); rover.command_v=.04; await steps(110); summary()
	await setup("articulation_on_block")
	terrain(Vector3(.7,.18,1.0),Vector3(1.06,.09,1.2))
	await steps(18); summary()
	await setup("differential_disabled_control")
	rover.differential_enabled=false
	terrain(Vector3(.7,.18,1.0),Vector3(1.06,.09,1.2))
	await steps(18); summary()
	for entry in [["uphill_10",-10,false],["downhill_10",10,false],["cross_slope_10",10,true],["uphill_25",-25,false]]:
		await setup(entry[0],entry[1],entry[2])
		await steps(10,false); rover.command_v=.04; await steps(35); summary()
	await setup("sand_proxy_20deg",-20,false,.25)
	await steps(10,false); rover.command_v=.04; await steps(20); summary()
	await setup("trapped_wheel_stall")
	terrain(Vector3(5,1,1),Vector3(0,.5,2.04))
	await steps(8,false); rover.command_v=.04; await steps(40); summary()
	for scale in [.5,1.5]:
		await setup("torque_sensitivity_"+str(scale),-10,false,.85,120,scale)
		await steps(8,false); rover.command_v=.04; await steps(25); summary()
	for scale in [.5,2.0]:
		await setup("differential_sensitivity_"+str(scale),0,false,.85,120,1,scale)
		terrain(Vector3(.7,.18,1.0),Vector3(1.06,.09,1.2))
		await steps(18); summary()
	for factor in [.5,2.0]:
		await setup("inertia_sensitivity_"+str(factor))
		for body in rover.bodies.values(): body.inertia*=factor
		await steps(10,false); rover.command_v=.04; await steps(25); summary()
	for offset in [-50,50]:
		await setup("mass_distribution_"+str(offset))
		rover.chassis.mass+=offset
		for rocker in rover.rockers: rocker.mass-=offset*.5
		await steps(10,false); rover.command_v=.04; await steps(25); summary()
	await setup("front_contact_loss")
	await steps(8,false)
	scene.get_child(0).queue_free()
	terrain(Vector3(100,.4,100),Vector3(0,-.6,0))
	terrain(Vector3(100,.4,50),Vector3(0,-.2,-24.5))
	rover.command_v=.04
	await steps(12);summary()
	trace.close()
	var file:=FileAccess.open("res://evidence/validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  ")); file.close()
	quit()
