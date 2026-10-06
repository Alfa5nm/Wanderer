extends Node3D

var target: RigidBody3D
var camera: Camera3D
var yaw := -0.55
var pitch := 0.38
var distance := 6.0
var actual_distance := 6.0
var focus := Vector3.ZERO
var initialized := false
var inspection := false
var test_pad := -1

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 54
	camera.near = 0.08
	camera.far = 300
	add_child(camera)
	camera.current = true

func reset_view() -> void:
	yaw = atan2(target.global_basis.z.x,target.global_basis.z.z)-0.55
	pitch = .38
	distance = 6

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x*.004
		pitch = clampf(pitch+event.relative.y*.003,0.12,1.1)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: distance=maxf(3.0,distance-.45)
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN: distance=minf(14.0,distance+.45)
	if event.is_action_pressed("camera_reset"): reset_view()
	if event.is_action_pressed("inspection"): inspection = not inspection

func _process(_dt: float) -> void:
	if not is_instance_valid(target): return
	# Wall-time smoothing stays consistent when engineering time is accelerated.
	var dt := minf(_dt/maxf(Engine.time_scale,.001),.05)
	distance=clampf(distance+Input.get_axis("zoom_in","zoom_out")*dt*3,3,14)
	if Input.get_connected_joypads().size()>0 or test_pad>=0:
		var pad := test_pad if test_pad>=0 else Input.get_connected_joypads()[0]
		var x := Input.get_joy_axis(pad,JOY_AXIS_RIGHT_X)
		var y := Input.get_joy_axis(pad,JOY_AXIS_RIGHT_Y)
		if absf(x)>.15: yaw-=x*dt*1.5
		if absf(y)>.15: pitch=clampf(pitch+y*dt,0.12,1.1)
	var desired_focus := target.global_position + Vector3.UP*.35
	if not initialized:
		focus=desired_focus; initialized=true
	focus=focus.lerp(desired_focus,1.0-exp(-dt*6.0))
	if inspection:
		camera.global_position=target.global_position+target.global_basis*Vector3(-.55,1.1,.65)
		camera.look_at(camera.global_position+target.global_basis.z*10,Vector3.UP)
		return
	var outward := Vector3(-sin(yaw)*cos(pitch),sin(pitch),-cos(yaw)*cos(pitch))
	var desired := focus+outward*distance
	# Sphere sweep from beyond the rover's own envelope includes terrain and rover collision bodies.
	var from := focus+outward*2.15
	var sphere := SphereShape3D.new()
	sphere.radius=.18
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=sphere
	query.transform=Transform3D(Basis.IDENTITY,from)
	query.motion=desired-from
	query.collision_mask=3
	var fractions := get_world_3d().direct_space_state.cast_motion(query)
	var permitted := 2.15+(distance-2.15)*fractions[0]
	# Also catch walls between the focus and the outside-of-rover start point.
	query.transform=Transform3D(Basis.IDENTITY,focus)
	query.motion=desired-focus
	query.collision_mask=1
	var terrain_hit := get_world_3d().direct_space_state.cast_motion(query)
	permitted=minf(permitted,distance*terrain_hit[0])
	actual_distance=minf(actual_distance,permitted)
	actual_distance=lerpf(actual_distance,permitted,1.0-exp(-dt*5))
	camera.global_position=focus+outward*actual_distance
	camera.look_at(focus,Vector3.UP)
