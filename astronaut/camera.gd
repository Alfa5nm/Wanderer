class_name AstronautCamera
extends Node3D

var actor: CharacterBody3D
var camera: Camera3D
var yaw := -0.55
var pitch := 0.3
var distance := 4.5
var focus := Vector3.ZERO
var enabled := false
var stick := Vector2.ZERO
var trigger_zoom := Vector2.ZERO

func _ready() -> void:
	camera=Camera3D.new(); camera.fov=54; camera.near=0.08; camera.far=30000
	add_child(camera)
	focus=actor.global_position+Vector3.UP*1.1

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		if event.axis==JOY_AXIS_RIGHT_X: stick.x=event.axis_value
		if event.axis==JOY_AXIS_RIGHT_Y: stick.y=event.axis_value
		if event.axis==JOY_AXIS_TRIGGER_LEFT: trigger_zoom.x=event.axis_value
		if event.axis==JOY_AXIS_TRIGGER_RIGHT: trigger_zoom.y=event.axis_value
	if not enabled: return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw-=event.relative.x*0.004; pitch=clampf(pitch+event.relative.y*0.003,-0.08,1.1)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: distance=maxf(2.2,distance-0.4)
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN: distance=minf(12,distance+0.4)
	if event.is_action_pressed("camera_reset"): yaw=actor.rotation.y-0.55; pitch=0.3; distance=4.5

func _process(delta: float) -> void:
	if not enabled: return
	var dt := minf(delta/maxf(Engine.time_scale,0.001),0.05)
	var axes := stick; var triggers := trigger_zoom
	if not Input.get_connected_joypads().is_empty():
		var pad: int = Input.get_connected_joypads()[0]
		axes=Vector2(Input.get_joy_axis(pad,JOY_AXIS_RIGHT_X),Input.get_joy_axis(pad,JOY_AXIS_RIGHT_Y))
		triggers=Vector2(Input.get_joy_axis(pad,JOY_AXIS_TRIGGER_LEFT),Input.get_joy_axis(pad,JOY_AXIS_TRIGGER_RIGHT))
	distance=clampf(distance+(triggers.x-triggers.y)*dt*4,2.2,12)
	if absf(axes.x)>0.15: yaw-=axes.x*dt*1.5
	if absf(axes.y)>0.15: pitch=clampf(pitch+axes.y*dt,-0.08,1.1)

	focus=focus.lerp(actor.global_position+Vector3.UP*1.1,1-exp(-dt*8))
	var direction := Vector3(-sin(yaw)*cos(pitch),sin(pitch),-cos(yaw)*cos(pitch))
	var query := PhysicsRayQueryParameters3D.create(focus,focus+direction*distance,3,[actor.get_rid()])
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	var length := distance if hit.is_empty() else maxf(0.45,focus.distance_to(hit.position)-0.2)
	camera.global_position=focus+direction*length
	camera.look_at(focus,Vector3.UP)
