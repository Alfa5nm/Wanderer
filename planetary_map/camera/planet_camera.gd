class_name PlanetCameraRig
extends Node3D

signal moved
signal focus_finished
@export var sensitivity: float = 0.004
@export var wheel_zoom_sensitivity: float = 0.16
@export var controller_orbit_speed: float = 1.1
@export var controller_zoom_speed: float = 5.0
@export var rotation_damping: float = 9.0
@export var zoom_damping: float = 7.0
@export var min_distance: float = 1.035
@export var max_distance: float = 6.0
var radius := 1.0
const RENDER_SCALE := 1000.0
var surface_service: PlanetSurfaceService
var camera: Camera3D
var yaw: float = deg_to_rad(80.0)
var pitch: float = deg_to_rad(12.0)
var distance: float = 3.4
var target_distance: float = 3.4
var velocity := Vector2.ZERO
var desired_velocity := Vector2.ZERO
var focus_tween: Tween
var focusing := false
var pending_drag := Vector2.ZERO
var dragging := false
var locked := false
var test_pad := -1

func _ready() -> void:
	min_distance *= radius
	max_distance *= radius
	distance *= radius
	target_distance *= radius
	camera = Camera3D.new()
	camera.fov = 42
	camera.near = 0.004*radius
	camera.far = 40*radius
	camera.current = true
	add_child(camera)
	update_camera()

func orbit_scale() -> float:
	return clampf((distance-radius)/radius,0.000025,1.0)

func orbit_drag(relative: Vector2, _dt: float) -> void:
	if locked: return
	cancel_focus()
	pending_drag += relative

func begin_drag() -> void:
	if locked: return
	cancel_focus()
	dragging=true
	velocity=Vector2.ZERO
	pending_drag=Vector2.ZERO

func end_drag() -> void:
	dragging=false
	# Stop exactly where the pointer leaves the globe; avoid post-drag camera sway.
	velocity=Vector2.ZERO

func zoom(amount: float) -> void:
	if locked: return
	cancel_focus()
	target_distance = clampf(radius+(target_distance-radius)*exp(amount*wheel_zoom_sensitivity), min_distance, max_distance)
	if amount<0: velocity*=exp(amount*0.08)

func cancel_focus() -> void:
	if focus_tween != null: focus_tween.kill()
	focus_tween=null
	focusing = false

func focus_on_coordinates(lat: float, lon: float, zoom_level: float, duration: float = -1.0) -> bool:
	if not PlanetCoordinates.valid(lat, lon) or not is_finite(zoom_level) or zoom_level<=1.0: return false
	cancel_focus()
	velocity = Vector2.ZERO
	focusing = true
	pending_drag=Vector2.ZERO
	var start := PlanetCoordinates.lat_lon_to_local(rad_to_deg(pitch),rad_to_deg(yaw))
	var finish := PlanetCoordinates.lat_lon_to_local(lat,lon)
	var angle := start.angle_to(finish)
	var initial_distance := distance
	target_distance = clampf(zoom_level*radius,min_distance,max_distance)
	var destination := target_distance
	var seconds := duration if duration>0 else clampf(0.8+angle*0.5+absf(log((destination-radius)/(distance-radius)))*0.1,0.8,2.8)
	var apex := maxf(initial_distance,destination)
	if angle>deg_to_rad(30): apex=maxf(apex,radius*(1.0+0.6*sin(angle*0.5)))
	apex=minf(apex,max_distance)
	# A tangent defines a stable great-circle path, including opposite targets.
	var tangent := finish-start*cos(angle)
	if tangent.length_squared()<0.00000001: tangent=start.cross(Vector3.UP if absf(start.y)<0.9 else Vector3.RIGHT)
	tangent=tangent.normalized()
	focus_tween=create_tween()
	focus_tween.tween_method(func(t: float):
		var eased := t*t*t*(t*(t*6.0-15.0)+10.0)
		var direction := start*cos(angle*eased)+tangent*sin(angle*eased)
		var geo := PlanetCoordinates.local_to_lat_lon(direction)
		yaw+=wrapf(deg_to_rad(geo.y)-yaw,-PI,PI)
		pitch=clampf(deg_to_rad(geo.x),-1.48,1.48)
		var clearance: float
		if angle>deg_to_rad(30):
			var u := smoothstep(0.0,0.5,t) if t<0.5 else smoothstep(0.5,1.0,t)
			clearance=exp(lerpf(log(initial_distance-radius),log(apex-radius),u)) if t<0.5 else exp(lerpf(log(apex-radius),log(destination-radius),u))
		else: clearance=exp(lerpf(log(initial_distance-radius),log(destination-radius),eased))
		distance=radius+clearance
		update_camera(),0.0,1.0,seconds)
	focus_tween.tween_callback(func(): distance=destination; focusing=false; update_camera(); focus_finished.emit())
	return true

func snapshot() -> Vector3:
	return Vector3(yaw, pitch, target_distance)

func restore(view: Vector3) -> void:
	focus_on_coordinates(rad_to_deg(view.y), rad_to_deg(view.x), view.z/radius, 0.8)

func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	if not locked:
		var pad := test_pad
		if pad < 0 and not Input.get_connected_joypads().is_empty(): pad = Input.get_connected_joypads()[0]
		desired_velocity = Vector2.ZERO
		if pad >= 0:
			var stick := Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
			if stick.length() > 0.18:
				cancel_focus()
				desired_velocity = Vector2(-stick.x, stick.y).normalized()*pow(clampf((stick.length()-0.18)/0.82,0,1),1.5)*controller_orbit_speed*orbit_scale()
			var zoom_axis := Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT)-Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT)
			if absf(zoom_axis)>0.12: zoom(-zoom_axis*dt*controller_zoom_speed)
		if not focusing:
			var damping := rotation_damping if desired_velocity.length()>0 else lerpf(24.0,12.0,orbit_scale())
			if not pending_drag.is_zero_approx():
				var size := camera.get_viewport().get_visible_rect().size
				var delta := Vector2(-pending_drag.x,pending_drag.y)*sensitivity*(900.0/maxf(size.y,1.0))*(tan(deg_to_rad(camera.fov)*0.5)/tan(deg_to_rad(42.0)*0.5))*orbit_scale()
				yaw+=delta.x
				pitch=clampf(pitch+delta.y,-1.48,1.48)
				velocity=Vector2.ZERO
				pending_drag=Vector2.ZERO
			elif not dragging:
				var factor := exp(-damping*dt)
				var old := velocity
				velocity=desired_velocity+(velocity-desired_velocity)*factor
				var delta := desired_velocity*dt+(old-desired_velocity)*(1.0-factor)/damping
				yaw+=delta.x
				pitch=clampf(pitch+delta.y,-1.48,1.48)
			if absf(pitch)>=1.48: velocity.y=0
			var clearance := exp(lerpf(log(maxf(distance-radius,radius*0.000025)),log(maxf(target_distance-radius,radius*0.000025)),1.0-exp(-zoom_damping*dt)))
			distance=clampf(radius+clearance,min_distance,max_distance)
	update_camera()

func update_camera() -> void:
	var lat := rad_to_deg(pitch)
	var lon := rad_to_deg(yaw)
	var ground := radius
	if surface_service!=null:
		ground = float(surface_service.sample(lat,lon).get("radial_m",surface_service.physical_radius_m))/surface_service.physical_radius_m*radius
	var clearance := maxf(distance-radius, radius*0.000025)
	var phi := deg_to_rad(lat)
	var theta := deg_to_rad(lon)
	var r := ground+clearance
	var tilt := (1.0-smoothstep(0.002,0.02,clearance/radius))*clearance*0.65 if surface_service!=null else 0.0
	var eye64: Array[float] = [cos(phi)*sin(theta)*r+sin(phi)*sin(theta)*tilt,sin(phi)*r-cos(phi)*tilt,cos(phi)*cos(theta)*r+sin(phi)*cos(theta)*tilt]
	var next := Vector3(eye64[0],eye64[1],eye64[2])
	var render_scale := RENDER_SCALE if surface_service!=null else 1.0
	camera.near = maxf(0.001,clearance*0.003*render_scale)
	camera.far = radius*12*render_scale
	if camera.position.distance_squared_to(next*render_scale)<0.0000000000000001: return
	camera.position = next*render_scale
	if surface_service!=null:
		surface_service.render_origin=next
		surface_service.render_origin64=eye64
		scale=Vector3.ONE
		position=-next*RENDER_SCALE
		var target64: Array[float] = [cos(phi)*sin(theta)*ground,sin(phi)*ground,cos(phi)*cos(theta)*ground]
		camera.look_at(PlanetSurfaceService.relative64(target64,eye64)*RENDER_SCALE,Vector3.UP)
	else: camera.look_at(Vector3.ZERO, Vector3.UP)
	moved.emit()

func _exit_tree() -> void:
	cancel_focus()
