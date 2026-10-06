class_name PlanetSelection
extends Node

signal selected(data: PlanetMarkerData, double_click: bool)
signal back_requested
signal pointer_changed(position: Vector2)
var surface_service: PlanetSurfaceService
var survey: PlanetSurveyGrid
var rig: PlanetCameraRig
var markers: PlanetMarkerManager
var region: PlanetRegion
var dragging := false
var drag_distance := 0.0
var press_position := Vector2.ZERO
var double_click := false
var controller_active := false
var enabled := true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		dragging = false
		rig.end_drag()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		controller_active = false
		pointer_changed.emit(event.position)
	if event is InputEventJoypadMotion or event is InputEventJoypadButton:
		controller_active = true
	if enabled and event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_A and survey!=null and survey.enabled and survey.visible:
		select_at(markers.size*0.5)
		get_viewport().set_input_as_handled()
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y,JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT]:
		# Orbit/zoom axes must not also navigate default Godot UI focus.
		get_viewport().set_input_as_handled()
	# Release is processed even over UI, preventing a stuck drag.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if dragging:
			dragging = false
			rig.end_drag()
			if enabled and drag_distance < 6.0: select_at(event.position, double_click)

func _unhandled_input(event: InputEvent) -> void:
	if not enabled: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			dragging = true
			rig.begin_drag()
			drag_distance = 0
			press_position = event.position
			double_click = event.double_click
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: rig.zoom(-1)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: rig.zoom(1)
	if event is InputEventMouseMotion and dragging:
		drag_distance += event.relative.length()
		if drag_distance >= 6.0: rig.orbit_drag(event.relative, get_process_delta_time())
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE: back_requested.emit()
		if event.keycode == KEY_ENTER: select_at(markers.size*0.5, false)
		if event.keycode == KEY_EQUAL: rig.zoom(-1)
		if event.keycode == KEY_MINUS: rig.zoom(1)
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_A: select_at(markers.size*0.5, false)
		if event.button_index == JOY_BUTTON_B: back_requested.emit()

func select_at(screen_position: Vector2, twice: bool = false) -> void:
	if survey!=null and survey.enabled and survey.visible:
		var inverse := markers.planet.global_transform.affine_inverse()
		var origin := inverse*rig.camera.project_ray_origin(screen_position)
		var direction := (inverse.basis*rig.camera.project_ray_normal(screen_position)).normalized()
		survey.select_at(surface_service.hit(origin,direction))
		return
	var picked := markers.pick(screen_position)
	if picked == null and (region != null or (survey!=null and survey.enabled)):
		var camera := rig.camera
		var inverse := markers.planet.global_transform.affine_inverse()
		var local_origin := inverse * camera.project_ray_origin(screen_position)
		var local_direction := (inverse.basis * camera.project_ray_normal(screen_position)).normalized()
		var hit := surface_service.hit(local_origin,local_direction) if surface_service!=null else PlanetCoordinates.surface_hit(local_origin, local_direction, markers.radius)
		if survey!=null and survey.enabled and hit!=Vector3.ZERO:
			survey.select_at(hit)
			return
		if hit != Vector3.ZERO:
			var anchor := PlanetCoordinates.lat_lon_to_local(region.latitude, region.longitude) if region!=null else Vector3.ZERO
			if region!=null and anchor.angle_to(hit.normalized()) < deg_to_rad(region.focus_extent_degrees): picked = region
	if picked != null: selected.emit(picked, twice)
