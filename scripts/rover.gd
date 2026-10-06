extends Node3D

const BodyScript = preload("res://scripts/telemetry_body.gd")
var p: Dictionary
var geometry: Dictionary
var bodies: Dictionary = {}
var wheels: Array[Dictionary] = []
var chassis: RigidBody3D
var rockers: Array[RigidBody3D] = []
var steering: Array[Dictionary] = []
var command_v := 0.0
var command_yaw := 0.0
var smooth_v := 0.0
var smooth_yaw := 0.0
var differential_error := 0.0
var differential_enabled := true
var torque_scale := 1.0
var differential_scale := 1.0
var spawn_offset := Vector3.ZERO
var spawn_basis := Basis.IDENTITY
var visual_enabled := true
var brake := false
var support_inferred := 0.0
var previous_momentum := Vector3.ZERO
var momentum_initialized := false

func value(key: String) -> float:
	return float(p[key].value)

func vector_value(key: String) -> Vector3:
	var v: Array = p[key].value
	return Vector3(v[0],v[1],v[2])

func rest(key: String) -> Vector3:
	if p.has("origin_"+key): return vector_value("origin_"+key)
	var a: Array = geometry.groups[key]
	return Vector3(a[0], a[1], a[2])

func _ready() -> void:
	p = JSON.parse_string(FileAccess.get_file_as_string("res://engineering_parameters.json"))
	geometry = JSON.parse_string(FileAccess.get_file_as_string("res://assets/geometry.json"))
	chassis = make_body("ChassisVisual", value("chassis_mass"), vector_value("chassis_inertia"))
	box_shape(chassis, vector_value("chassis_collision_size"))
	for side in ["L", "R"]:
		var rocker := make_body("Rocker_"+side, value("rocker_mass"), vector_value("rocker_inertia"))
		rockers.append(rocker)
		sphere_shape(rocker, value("rocker_collision_radius"))
		hinge(chassis, rocker, rest("Rocker_"+side), Vector3.RIGHT, value("rocker_limit"))
		var bogie := make_body("Bogie_"+side, value("bogie_mass"), vector_value("bogie_inertia"))
		sphere_shape(bogie, value("bogie_collision_radius"))
		hinge(rocker, bogie, rest("Bogie_"+side), Vector3.RIGHT, value("bogie_limit"))
		for station in ["F", "M", "R"]:
			var id: String = station+side
			var parent: RigidBody3D = rocker if station == "F" else bogie
			var carrier: RigidBody3D = parent
			if station != "M":
				carrier = make_body("Carrier_"+id, value("carrier_mass"), vector_value("carrier_inertia"))
				sphere_shape(carrier, value("carrier_collision_radius"))
				hinge(parent, carrier, rest("Carrier_"+id), Vector3.UP, value("steering_limit"))
				steering.append({"body": carrier, "parent": parent, "target": 0.0, "angle": 0.0, "command": 0.0, "id": id})
			var wheel := make_body("Wheel_"+id, value("wheel_mass"), vector_value("wheel_inertia"))
			var shape := CylinderShape3D.new()
			shape.radius = value("wheel_radius")
			shape.height = value("wheel_width")
			var collision := CollisionShape3D.new()
			collision.shape = shape
			collision.rotation.z = PI/2
			wheel.add_child(collision)
			hinge(carrier, wheel, rest("Wheel_"+id), Vector3.RIGHT, 0.0)
			wheels.append({"id":id, "body":wheel, "parent":carrier, "steered":station!="M", "target":0.0, "rate":0.0, "torque":0.0, "integral":0.0, "slip":0.0, "lateral_slip":0.0})
	if visual_enabled:
		var asset: Node3D = load("res://assets/curiosity.glb").instantiate()
		add_child(asset)
		for key in bodies:
			var group := asset.find_child(key, true, false) as Node3D
			if group:
				group.reparent(bodies[key], false)
				group.transform = Transform3D.IDENTITY
			else:
				push_error("Missing exported assembly: "+key)
		asset.queue_free()

func make_body(key: String, mass_kg: float, inertia_estimate: Vector3) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.set_script(BodyScript)
	b.name = key
	b.mass = mass_kg
	b.gravity_scale = value("gravity")/float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	b.inertia = inertia_estimate
	b.can_sleep = false
	b.linear_damp = value("linear_damping")
	b.angular_damp = value("angular_damping")
	b.collision_layer = 2
	b.collision_mask = 3
	b.contact_monitor = true
	b.max_contacts_reported = 16
	b.continuous_cd = true
	var material := PhysicsMaterial.new()
	material.friction = value("wheel_friction")
	material.bounce = 0
	b.physics_material_override = material
	add_child(b)
	b.global_transform = Transform3D(spawn_basis, spawn_offset + spawn_basis * rest(key))
	bodies[key] = b
	return b

func sphere_shape(b: RigidBody3D, radius: float) -> void:
	var c := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	c.shape = s
	b.add_child(c)

func box_shape(b: RigidBody3D, size: Vector3) -> void:
	var c := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	c.shape = s
	b.add_child(c)

func hinge(a: RigidBody3D, b: RigidBody3D, point: Vector3, axis: Vector3, limit: float) -> void:
	var j := HingeJoint3D.new()
	j.name = "Joint_"+str(b.name)
	add_child(j)
	# HingeJoint3D's free rotation axis is its local Z.
	var jb := Basis(Vector3.UP, PI/2) if axis == Vector3.RIGHT else Basis(Vector3.RIGHT, -PI/2)
	j.global_transform = Transform3D(spawn_basis * jb, spawn_offset + spawn_basis * point)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	j.exclude_nodes_from_collision = true
	if limit > 0:
		j.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		j.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -limit)
		j.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, limit)

func _physics_process(dt: float) -> void:
	if not is_instance_valid(chassis): return
	var momentum := Vector3.ZERO
	for b in bodies.values(): momentum += b.mass*b.linear_velocity
	if momentum_initialized:
		support_inferred = (momentum.y-previous_momentum.y)/dt+value("total_mass")*value("gravity")+value("linear_damping")*momentum.y
	previous_momentum=momentum
	momentum_initialized=true
	smooth_v = move_toward(smooth_v, 0.0 if brake else command_v, value("acceleration")*dt)
	smooth_yaw = move_toward(smooth_yaw, 0.0 if brake else command_yaw, value("yaw_acceleration")*dt)
	apply_differential()
	var readiness := 1.0
	# ICR origin follows the actual middle axle, rather than the chassis origin.
	var origin: Vector3 = (bodies.Wheel_ML.global_position+bodies.Wheel_MR.global_position)*0.5
	for s in steering:
		var wheel: RigidBody3D = bodies["Wheel_"+s.id]
		var r: Vector3 = chassis.global_basis.inverse()*(wheel.global_position-origin)
		var forward := smooth_v-smooth_yaw*r.x
		var lateral := smooth_yaw*r.z
		var desired := atan2(lateral, forward) if absf(forward)+absf(lateral)>0.00001 else float(s.target)
		if desired>PI/2: desired-=PI
		if desired< -PI/2: desired+=PI
		desired = clampf(desired, -value("steering_limit"), value("steering_limit"))
		s.target = desired
		s.command = move_toward(float(s.command), desired, value("steering_rate")*dt)
		var relative: Basis = s.parent.global_basis.inverse()*s.body.global_basis
		s.angle = atan2(relative.z.x, relative.z.z)
		var axis: Vector3 = s.parent.global_basis.y
		var rate: float = (s.body.angular_velocity-s.parent.angular_velocity).dot(axis)
		var torque := clampf(value("steering_kp")*(float(s.command)-float(s.angle))-value("steering_kd")*rate, -value("steering_torque"), value("steering_torque"))
		s.body.apply_torque(axis*torque)
		s.parent.apply_torque(-axis*torque)
		readiness = minf(readiness, clampf((value("steering_readiness")-absf(desired-float(s.angle)))/(value("steering_readiness")*.5),0.0,1.0))
	for w in wheels:
		var wheel: RigidBody3D = w.body
		var carrier: RigidBody3D = w.parent
		var axis := carrier.global_basis.x.normalized()
		var normal: Vector3 = wheel.contact_normal
		var rolling := axis.cross(normal).normalized()
		var r: Vector3 = chassis.global_basis.inverse()*(wheel.global_position-origin)
		var desired_world := chassis.global_basis*Vector3(smooth_yaw*r.z,0,smooth_v-smooth_yaw*r.x)
		w.target = desired_world.dot(rolling)/value("wheel_radius")*readiness
		w.rate = (wheel.angular_velocity-carrier.angular_velocity).dot(axis)
		var error: float = float(w.target)-float(w.rate)
		var cap := value("drive_torque")*torque_scale
		# Contact-loss damping, not JPL's flight traction-control algorithm.
		if wheel.contacts==0: cap *= value("floating_torque_fraction")
		w.integral = clampf(float(w.integral)+error*dt*value("drive_ki"),-cap,cap)
		w.torque = clampf(value("drive_kp")*error+float(w.integral),-cap,cap)
		wheel.apply_torque(axis*float(w.torque))
		carrier.apply_torque(-axis*float(w.torque))
		var surface_speed: float = float(w.rate)*value("wheel_radius")
		var ground_speed := wheel.linear_velocity.dot(rolling)
		w.slip = (surface_speed-ground_speed)/maxf(maxf(absf(surface_speed),absf(ground_speed)),value("slip_denominator_floor"))
		w.lateral_slip = wheel.linear_velocity.dot(axis)

func apply_differential() -> void:
	var axis := chassis.global_basis.x
	var q := 0.0
	var qdot := 0.0
	for rocker in rockers:
		var relative := chassis.global_basis.inverse()*rocker.global_basis
		q += atan2(relative.y.z, relative.y.y)
		qdot += (rocker.angular_velocity-chassis.angular_velocity).dot(axis)
	differential_error = q
	if not differential_enabled: return
	# Compliant gear constraint: potential .5*k*(qL+qR)^2.
	# Equal generalized torques on rockers, opposite summed reaction on chassis.
	var torque := clampf(-value("differential_stiffness")*differential_scale*q-value("differential_damping")*qdot,-value("differential_torque"),value("differential_torque"))
	for rocker in rockers: rocker.apply_torque(axis*torque)
	chassis.apply_torque(-2*axis*torque)

func telemetry() -> Dictionary:
	var rows: Array = []
	var support := 0.0
	var total_mass := 0.0
	for b in bodies.values():
		support+=b.support
		total_mass+=b.mass
	for w in wheels:
		var angle := 0.0
		var target_angle := 0.0
		for s in steering:
			if s.id==w.id:
				angle=rad_to_deg(s.angle)
				target_angle=rad_to_deg(s.target)
		rows.append({"id":w.id,"rate":w.rate,"target":w.target,"torque":w.torque,"slip":w.slip,"lateral_m_s":w.lateral_slip,"contacts":w.body.contacts,"jolt_contact_proxy_n":w.body.support,"steer_deg":angle,"steer_target_deg":target_angle})
	return {"position":[chassis.position.x,chassis.position.y,chassis.position.z],"speed":chassis.linear_velocity.length(),"forward_speed":chassis.linear_velocity.dot(chassis.global_basis.z),"heading":rad_to_deg(atan2(chassis.global_basis.z.x,chassis.global_basis.z.z)),"pitch":rad_to_deg(chassis.rotation.x),"roll":rad_to_deg(chassis.rotation.z),"differential_error_deg":rad_to_deg(differential_error),"support_n":support_inferred,"jolt_contact_proxy_n":support,"mass_kg":total_mass,"wheels":rows}
