extends SceneTree

var checks: Dictionary={}
var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func ticks(n: int) -> void:
	for i in n: await physics_frame

func inject(event: InputEvent) -> void:
	Input.parse_input_event(event.duplicate())
	Input.flush_buffered_events()

func key(code: int, pressed: bool=true) -> void:
	var e:=InputEventKey.new(); e.physical_keycode=code;e.keycode=code;e.pressed=pressed;inject(e)

func tap(code: int) -> void:
	key(code); await ticks(2); key(code,false); await ticks(2)

func screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	Input.use_accumulated_input=false
	world=load("res://main.tscn").instantiate();root.add_child(world)
	world.accelerated=false;world.apply_mode()
	await ticks(1200)
	var start: Vector3=world.rover.chassis.position
	key(KEY_W);await ticks(5)
	checks.keyboard_command_m_s=world.rover.command_v
	# Keep the synthetic hold alive if the desktop window loses focus during automation.
	for i in 475:
		key(KEY_W);await ticks(1)
	key(KEY_W,false)
	checks.keyboard_distance_m=world.rover.chassis.position.z-start.z
	checks.keyboard_drive=world.rover.chassis.position.z-start.z>.07
	await ticks(300)
	await tap(KEY_F1);checks.overlay=world.panel.visible
	await tap(KEY_TAB);checks.time_mode=Engine.time_scale==6.0 and Engine.physics_ticks_per_second==720
	checks.observed_time_scale=Engine.time_scale
	checks.observed_physics_hz=Engine.physics_ticks_per_second
	checks.physics_dt=absf(world.rover.get_physics_process_delta_time()-1.0/120)<.00001
	await tap(KEY_TAB)
	var old_yaw: float=world.orbit.yaw
	var button:=InputEventMouseButton.new();button.button_index=MOUSE_BUTTON_RIGHT;button.pressed=true;inject(button)
	var motion:=InputEventMouseMotion.new();motion.relative=Vector2(90,-20);inject(motion);await ticks(2)
	checks.mouse_orbit=absf(world.orbit.yaw-old_yaw)>.1
	button.pressed=false;inject(button)
	var scroll:=InputEventMouseButton.new();scroll.button_index=MOUSE_BUTTON_WHEEL_UP;scroll.pressed=true;inject(scroll);await ticks(2)
	checks.zoom=world.orbit.distance<6
	await tap(KEY_C);checks.camera_reset=world.orbit.distance==6
	await tap(KEY_V);checks.rover_pov=world.orbit.inspection
	await tap(KEY_V)
	# Hardware enumeration cannot be injected. Override the polled device id for this test only.
	world.test_pad=0
	world.orbit.test_pad=0
	var axis:=InputEventJoypadMotion.new();axis.device=0;axis.axis=JOY_AXIS_LEFT_Y;axis.axis_value=-1;inject(axis)
	await ticks(10);checks.gamepad_drive=world.rover.command_v>.039
	axis.axis=JOY_AXIS_LEFT_X;axis.axis_value=-1;inject(axis)
	await ticks(10);checks.gamepad_turn=world.rover.command_yaw>.024
	var zoom_before: float=world.orbit.distance
	var zoom_button:=InputEventJoypadButton.new();zoom_button.device=0;zoom_button.button_index=JOY_BUTTON_RIGHT_SHOULDER;zoom_button.pressed=true;inject(zoom_button)
	await ticks(30);checks.gamepad_zoom=world.orbit.distance<zoom_before
	zoom_button.pressed=false;inject(zoom_button)
	key(KEY_SPACE);await ticks(5);checks.brake_input=world.rover.brake;key(KEY_SPACE,false)
	axis.axis=JOY_AXIS_RIGHT_X;axis.axis_value=.8;inject(axis)
	old_yaw=world.orbit.yaw;await ticks(30);checks.gamepad_camera=world.orbit.yaw<old_yaw
	world.test_pad=-1;world.orbit.test_pad=-1
	await tap(KEY_R);await ticks(600);checks.recovery=world.rover.chassis.position.z<.2
	world.orbit.yaw=2.5
	await ticks(90)
	await screenshot("res://evidence/runtime_engineering.png")
	await tap(KEY_F1);world.orbit.reset_view();await ticks(90)
	await screenshot("res://evidence/runtime.png")
	var old_distance: float=world.orbit.actual_distance
	var obstruction: StaticBody3D=world.block("Camera test wall",world.orbit.focus+Vector3(-sin(world.orbit.yaw),0,-cos(world.orbit.yaw))*3+Vector3.UP,Vector3(3,5,.4),Color.GRAY)
	await ticks(120);checks.camera_obstacle=world.orbit.actual_distance<old_distance-.2
	obstruction.queue_free()
	checks["synthetic_gamepad_note"]="Input events injected through Godot Input; no physical controller was available."
	var file:=FileAccess.open("res://evidence/controls_validation.json",FileAccess.WRITE);file.store_string(JSON.stringify(checks,"  "));file.close()
	print(JSON.stringify(checks))
	var failed := false
	for result in checks.values():
		if typeof(result)==TYPE_BOOL and not result: failed=true
	quit(1 if failed else 0)

