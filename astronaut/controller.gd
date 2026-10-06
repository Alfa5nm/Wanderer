class_name MarsAstronaut
extends CharacterBody3D

signal state_changed(value: String)
var controlled := false
var injected_stick := Vector2.ZERO
var world: Node
var model: Node3D
var skeleton: Skeleton3D
var animation: AnimationPlayer
var camera_rig: AstronautCamera
var shape: CollisionShape3D
var state := "idle"
var phase := 0.0
var recovery_clock := 0.0
var lean := 0.0
var feet: Array[Dictionary] = []
var solver: TwoBoneIK3D
var simulator: PhysicalBoneSimulator3D
var physical_bones: Array[PhysicalBone3D] = []
var fall_clock := 0.0
var unsupported := 0.0
var last_floor := Vector3.ZERO
var pelvis_offset := 0.0
var metrics := {"ik_us":0,"planted_drift_m":0.0,"solver_error_m":0.0,"contact_samples":0,"clamped_targets":0,"recoveries":0}

func find_type(node: Node,type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var found := find_type(child,type)
		if found!=null: return found
	return null

func _ready() -> void:
	name="Astronaut"
	collision_layer=4; collision_mask=3
	floor_max_angle=deg_to_rad(25); floor_snap_length=0.25
	shape=CollisionShape3D.new()
	var capsule := CapsuleShape3D.new(); capsule.radius=0.33; capsule.height=1.8
	shape.shape=capsule; shape.position.y=0.9; add_child(shape)
	model=load("res://assets/astronaut/astronaut.glb").instantiate()
	add_child(model)
	skeleton=find_type(model,"Skeleton3D") as Skeleton3D
	animation=find_type(model,"AnimationPlayer") as AnimationPlayer
	if animation!=null:
		for key in animation.get_animation_list():
			if String(key).contains("walk") or String(key).ends_with("idle") or String(key).ends_with("brace") or String(key).contains("turn_"):
				animation.get_animation(key).loop_mode=Animation.LOOP_LINEAR
	camera_rig=AstronautCamera.new(); camera_rig.actor=self
	get_parent().add_child.call_deferred(camera_rig)
	var contacts := SkeletonModifier3D.new()
	contacts.set_script(load("res://astronaut/gait_contacts.gd")); contacts.actor=self
	skeleton.add_child(contacts)
	configure_ik()
	var alignment := SkeletonModifier3D.new()
	alignment.set_script(load("res://astronaut/foot_alignment.gd")); alignment.actor=self
	skeleton.add_child(alignment)
	configure_ragdoll()
	skeleton.skeleton_updated.connect(measure_contacts)
	last_floor=global_position
	play_clip("idle")

func configure_ik() -> void:
	solver=TwoBoneIK3D.new(); solver.name="FootIK"; solver.setting_count=2
	skeleton.add_child(solver)
	for i in 2:
		var side: String = "L" if i==0 else "R"
		var target := Node3D.new(); target.name="FootTarget"+side; add_child(target); target.top_level=true
		var pole := Node3D.new(); pole.name="KneePole"+side; add_child(pole); pole.top_level=true
		solver.set_root_bone_name(i,"thigh."+side)
		solver.set_middle_bone_name(i,"shin."+side)
		solver.set_end_bone_name(i,"foot."+side)
		solver.set_target_node(i,solver.get_path_to(target))
		solver.set_pole_node(i,solver.get_path_to(pole))
		var id := skeleton.find_bone("foot."+side)
		feet.append({"target":target,"pole":pole,"id":id,"planted":false,"anchor":Vector3.ZERO,"support":false,"normal":Vector3.UP,"heading":Vector3.FORWARD})

func configure_ragdoll() -> void:
	simulator=PhysicalBoneSimulator3D.new(); simulator.name="FallPhysics"
	skeleton.add_child(simulator)
	for bone_name in ["hips","chest","head","upper_arm.L","forearm.L","upper_arm.R","forearm.R","thigh.L","shin.L","foot.L","thigh.R","shin.R","foot.R"]:
		var id := skeleton.find_bone(bone_name)
		if id<0: continue
		var bone := PhysicalBone3D.new(); bone.bone_name=bone_name; bone.name="Physical_"+bone_name
		bone.mass=20.0 if bone_name=="hips" else 18.0 if bone_name=="chest" else 4.0
		bone.collision_layer=8; bone.collision_mask=3
		bone.joint_type=PhysicalBone3D.JOINT_TYPE_CONE
		var collider := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius=0.10 if "arm" in bone_name or "shin" in bone_name else 0.17
		capsule.height=maxf(capsule.radius*2,0.30 if "arm" in bone_name or "shin" in bone_name else 0.45)
		collider.shape=capsule
		bone.add_child(collider); simulator.add_child(bone)
		bone.body_offset=Transform3D(Basis.IDENTITY,Vector3(0,0.12,0))
		bone.set("joint_constraints/swing_span",35.0); bone.set("joint_constraints/twist_span",20.0)
		physical_bones.append(bone)
	simulator.active=false

func play_clip(clip: String) -> void:
	if animation==null: return
	for key in animation.get_animation_list():
		if String(key)==clip or String(key).ends_with("/"+clip) or String(key).ends_with("|"+clip):
			if animation.current_animation!=key:
				var keep_cycle := String(animation.current_animation).contains("walk") and String(key).contains("walk")
				var cycle := animation.current_animation_position/maxf(animation.current_animation_length,0.001) if keep_cycle else 0.0
				animation.play(key,0.15)
				if keep_cycle: animation.seek(cycle*animation.get_animation(key).length,true)
			return

func support(point: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*0.5,point-Vector3.UP*0.6,3,[get_rid()]))

func _input(event: InputEvent) -> void:
	if not event is InputEventJoypadMotion: return
	if event.axis==JOY_AXIS_LEFT_X: injected_stick.x=event.axis_value
	if event.axis==JOY_AXIS_LEFT_Y: injected_stick.y=event.axis_value

func _physics_process(dt: float) -> void:
	if skeleton==null: return
	if state=="fallen":
		fall_clock+=dt
		if fall_clock>2 and (Input.is_action_just_pressed("reset_rover") or not controlled): recover()
		return
	var input := Vector2.ZERO
	if controlled:
		input=Input.get_vector("left","right","forward","reverse")
		var stick := injected_stick
		if not Input.get_connected_joypads().is_empty():
			var pad: int = Input.get_connected_joypads()[0]
			stick=Vector2(Input.get_joy_axis(pad,JOY_AXIS_LEFT_X),Input.get_joy_axis(pad,JOY_AXIS_LEFT_Y))
		if stick.length()>0.15: input=stick.limit_length(1.0)
	var brace: bool = controlled and Input.is_action_pressed("brake")
	recovery_clock=maxf(0,recovery_clock-dt/maxf(Engine.time_scale,0.001))
	if recovery_clock>0: input=Vector2.ZERO
	var fast: bool = controlled and Input.is_physical_key_pressed(KEY_SHIFT)
	var speed := 1.6 if fast else 1.0
	var direction := Vector3.ZERO
	if input.length()>0.1 and not brace:
		var forward := Vector3(sin(camera_rig.yaw),0,cos(camera_rig.yaw))
		direction=(forward*(-input.y)+Vector3(forward.z,0,-forward.x)*input.x).normalized()
		rotation.y=lerp_angle(rotation.y,atan2(direction.x,direction.z),minf(1,dt*8))
	var previous := velocity
	var turn_delta := wrapf(atan2(direction.x,direction.z)-rotation.y,-PI,PI) if direction.length()>0 else 0.0
	var acceleration := 2.0 if direction.length()>0 else 4.0
	velocity.x=move_toward(velocity.x,direction.x*speed,acceleration*dt)
	velocity.z=move_toward(velocity.z,direction.z*speed,acceleration*dt)
	if not is_on_floor(): velocity.y-=3.71*dt
	else: velocity.y=-0.15
	var impact := velocity.length()
	step_up(direction,dt)
	move_and_slide()
	if is_on_floor():
		last_floor=global_position; unsupported=0
	else: unsupported+=dt
	if (unsupported>1.0 and velocity.y < -2.5) or (get_slide_collision_count()>0 and impact>4.5): fall(); return
	var horizontal := Vector2(velocity.x,velocity.z).length()
	if animation!=null and not String(animation.current_animation).is_empty() and animation.current_animation_length>0:
		phase=fposmod(animation.current_animation_position/animation.current_animation_length,1.0)
	var previous_state := state
	state="recovery" if recovery_clock>0 else "brace" if brace else "stop" if direction.length()<0.1 and horizontal>0.08 else "fast_walk" if horizontal>1.15 else "walk" if horizontal>0.08 else "turn_left" if absf(turn_delta)>0.65 and turn_delta<0 else "turn_right" if absf(turn_delta)>0.65 else "idle"
	if state in ["walk","fast_walk"] and not previous_state in ["walk","fast_walk"]:
		for foot in feet: foot.planted=false
	var accel := (velocity-previous)/maxf(dt,0.0001)
	var slope_lean := get_floor_normal().dot(global_basis.z) if is_on_floor() else 0.0
	lean=clampf(accel.dot(global_basis.z)*0.025+horizontal*0.035+slope_lean*0.12+(0.05 if brace else 0.0),-0.12,0.12)
	play_clip(state)
	if animation!=null: animation.speed_scale=maxf(0.25,horizontal/(1.6 if fast else 1.0)) if horizontal>0.08 else 1.0/maxf(Engine.time_scale,0.001)


func measure_contacts() -> void:
	if state=="fallen": return
	for foot in feet:
		if not foot.planted or not foot.support: continue
		var actual: Vector3 = (skeleton.global_transform*skeleton.get_bone_global_pose(foot.id)).origin
		var target: Vector3 = foot.target.global_position
		metrics.solver_error_m=maxf(metrics.solver_error_m,Vector2(actual.x-target.x,actual.z-target.z).length())
		var anchor: Vector3 = foot.anchor
		metrics.planted_drift_m=maxf(metrics.planted_drift_m,Vector2(actual.x-anchor.x,actual.z-anchor.z).length())
		metrics.contact_samples+=1

func step_up(direction: Vector3,dt: float) -> void:
	if not is_on_floor() or direction.length()<0.1: return
	var motion := direction*maxf(0.08,Vector2(velocity.x,velocity.z).length()*dt)
	var obstacle := KinematicCollision3D.new()
	if test_move(global_transform,motion,obstacle) and obstacle.get_normal().y<cos(floor_max_angle):
		var raised := global_transform; raised.origin.y+=0.25
		# Place the capsule center beyond the rounded leading edge before checking support.
		var step_motion := direction*maxf(0.40,motion.length())
		if not test_move(global_transform,Vector3.UP*0.25) and not test_move(raised,step_motion):
			var down := KinematicCollision3D.new()
			if test_move(Transform3D(raised.basis,raised.origin+step_motion),Vector3.DOWN*0.3,down) and down.get_normal().y>=cos(deg_to_rad(25)):
				global_position+=step_motion+Vector3.UP*(0.25-down.get_travel().length())
				for foot in feet: foot.planted=false; foot.support=false

func update_ik(speed: float,dt: float) -> void:
	var began := Time.get_ticks_usec()
	var minimum := 0.0
	if animation!=null and not String(animation.current_animation).is_empty() and animation.current_animation_length>0:
		phase=fposmod(animation.current_animation_position/animation.current_animation_length,1.0)
	for i in 2:
		var foot: Dictionary = feet[i]
		# This runs before TwoBoneIK, using this frame's untouched animation pose.
		var pose := skeleton.global_transform*skeleton.get_bone_global_pose(foot.id)
		var hit := support(pose.origin)
		var toe := support(pose.origin+global_basis.z*0.12)
		var heel := support(pose.origin-global_basis.z*0.08)
		foot.support=not hit.is_empty() and not toe.is_empty() and not heel.is_empty()
		var cycle := fposmod(phase+i*0.5,1.0)
		var walking := state in ["walk","fast_walk"] and speed>0.08
		var stance: bool = not walking or cycle<0.60
		var desired: Vector3 = pose.origin
		if foot.support:
			foot.normal=(hit.normal+toe.normal+heel.normal).normalized()
			if stance:
				desired=hit.position+Vector3.UP*0.10
				if not foot.planted: foot.anchor=desired; foot.heading=global_basis.z; foot.planted=true
				# Release on large turns/step transfers, rather than crossing the legs.
				if foot.anchor.distance_to(desired)>0.40 or foot.heading.dot(global_basis.z)<cos(deg_to_rad(20)): foot.planted=false
				else: desired=foot.anchor
			else:
				foot.planted=false
				# Preserve authored clearance; ground adaptation cannot cancel swing lift.
				var lift := (0.105 if state=="fast_walk" else 0.085)*pow(sin(PI*(cycle-0.60)/0.40),2)
				desired.y=hit.position.y+0.10+lift
		else: foot.planted=false
		var root_id := skeleton.find_bone("thigh.L" if i==0 else "thigh.R")
		var middle_id := skeleton.find_bone("shin.L" if i==0 else "shin.R")
		var root := skeleton.global_transform*skeleton.get_bone_global_pose(root_id)
		var length := skeleton.get_bone_rest(middle_id).origin.length()+skeleton.get_bone_rest(foot.id).origin.length()
		var horizontal_reach := Vector2(root.origin.x-desired.x,root.origin.z-desired.z).length()
		var reach := length*0.995
		var allowed_height := sqrt(maxf(0,reach*reach-horizontal_reach*horizontal_reach))
		var required_offset := desired.y+allowed_height-root.origin.y+pelvis_offset
		if foot.planted:
			if required_offset < -0.15 or horizontal_reach>reach:
				foot.planted=false; desired=pose.origin; metrics.clamped_targets+=1
			else: minimum=minf(minimum,required_offset)
		foot.target.global_position=desired
		# Anatomical hip lane, forward knee bend; never send L/R poles across the body.
		foot.pole.global_position=root.origin+global_basis.z*0.8
	minimum=clampf(minimum,-0.15,0.0)
	pelvis_offset=minimum if minimum<pelvis_offset else lerpf(pelvis_offset,minimum,1-exp(-dt*16))
	model.position.y=pelvis_offset
	metrics.ik_us=maxi(metrics.ik_us,int(Time.get_ticks_usec()-began))

func fall() -> void:
	if state=="fallen": return
	state="fallen"; fall_clock=0
	if animation!=null: animation.stop()
	solver.active=false; simulator.active=true
	shape.set_deferred("disabled",true)
	simulator.physical_bones_start_simulation()
	state_changed.emit(state)

func recover() -> bool:
	var stable := support(last_floor+Vector3.UP*0.5)
	if stable.is_empty() or stable.normal.y<cos(deg_to_rad(25)): return false
	var candidate := Transform3D(Basis.IDENTITY,stable.position+Vector3.UP*0.05)
	var query := PhysicsShapeQueryParameters3D.new(); query.shape=shape.shape
	query.transform=Transform3D(candidate.basis,candidate.origin+Vector3.UP*0.9)
	query.collision_mask=3; query.exclude=[get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	simulator.physical_bones_stop_simulation(); simulator.active=false
	global_transform=candidate; velocity=Vector3.ZERO; solver.active=true
	shape.set_deferred("disabled",false); state="recovery"
	recovery_clock=0.8
	play_clip("recovery"); metrics.recoveries+=1; state_changed.emit(state)
	return true

func respawn(point: Vector3) -> void:
	simulator.physical_bones_stop_simulation(); simulator.active=false
	global_position=point; last_floor=point; velocity=Vector3.ZERO; unsupported=0
	model.position=Vector3.ZERO; pelvis_offset=0; recovery_clock=0
	shape.set_deferred("disabled",false); state="idle"; solver.active=true
	for foot in feet: foot.planted=false
	play_clip("idle")
