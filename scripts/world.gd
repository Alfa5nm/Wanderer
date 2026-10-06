extends Node3D

const RoverScript = preload("res://scripts/rover.gd")
const CameraScript = preload("res://scripts/orbit_camera.gd")
var rover: Node3D
var orbit: Node3D
var hud: Label
var panel: Label
var mode_label: Label
var accelerated := true
var engineering := false
var elapsed := 0.0
var screenshot_mode := false
var test_pad := -1
var panel_back: ColorRect
var terrain_parameters: Dictionary
var frame_samples: Array[float] = []

func _ready() -> void:
	inputs()
	terrain_parameters=JSON.parse_string(FileAccess.get_file_as_string("res://engineering_parameters.json"))
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode=Environment.BG_SKY
	var sky := Sky.new()
	var atmosphere := ProceduralSkyMaterial.new()
	atmosphere.sky_top_color=Color("362b2a")
	atmosphere.sky_horizon_color=Color("b28b68")
	atmosphere.ground_bottom_color=Color("3d2820")
	atmosphere.ground_horizon_color=Color("b28b68")
	sky.sky_material=atmosphere
	env.sky=sky
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("d5c3af")
	env.ambient_light_energy=.55
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.environment=env; add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-43,-32,0)
	sun.light_color=Color("ffe3bb")
	sun.light_energy=1.05
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=65
	add_child(sun)
	make_terrain()
	spawn_rover()
	make_hud()
	screenshot_mode="--capture" in OS.get_cmdline_user_args()
	apply_mode()

func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color=color
	m.roughness=.95
	return m

func block(label: String, center: Vector3, size: Vector3, color: Color, rotation_z: float=0, rotation_x: float=0, friction: float=.85) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name=label.replace(" ","_")
	b.position=center; b.rotation=Vector3(rotation_x,0,rotation_z)
	var shape := BoxShape3D.new(); shape.size=size
	var c := CollisionShape3D.new(); c.shape=shape; b.add_child(c)
	var mesh := MeshInstance3D.new(); var box := BoxMesh.new(); box.size=size
	mesh.mesh=box; mesh.material_override=material(color); b.add_child(mesh)
	if size.x>3 and size.z>3:
		var dust := ShaderMaterial.new()
		dust.shader=load("res://assets/ground.gdshader")
		dust.set_shader_parameter("dust_color",Vector3(color.r,color.g,color.b)*.68)
		mesh.material_override=dust
	var pm := PhysicsMaterial.new(); pm.friction=friction; b.physics_material_override=pm
	if label=="Level ground": pm.friction=terrain_parameters.rock_friction.value
	if label=="Regolith": pm.friction=terrain_parameters.regolith_friction.value
	if label=="Sand proxy": pm.friction=terrain_parameters.sand_friction.value
	add_child(b)
	return b

func signpost(text: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text=text; label.position=pos; label.font_size=44; label.pixel_size=.004
	label.modulate=Color("f7d8aa"); label.outline_modulate=Color("35241d")
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func make_terrain() -> void:
	block("Level ground",Vector3(0,-.15,0),Vector3(160,.3,160),Color("81563e"))
	block("Regolith",Vector3(9,.005,0),Vector3(7,.01,14),Color("95694a"),0,0,.6)
	block("Sand proxy",Vector3(-10,.008,0),Vector3(7,.016,14),Color("b38756"),0,0,.25)
	block("100 mm step",Vector3(1.05,.05,4),Vector3(.7,.1,1.5),Color("655347"))
	block("200 mm step",Vector3(-1.06,.1,8),Vector3(.7,.2,1.4),Color("645247"))
	block("Cross slope",Vector3(9,.55,15),Vector3(6,.25,7),Color("8c6147"),deg_to_rad(10))
	block("Uphill 10",Vector3(0,.73,18),Vector3(5,.35,10),Color("73513f"),0,deg_to_rad(-10))
	block("Uphill 20",Vector3(-10,1.14,18),Vector3(5,.35,7),Color("74503d"),0,deg_to_rad(-20))
	for z in range(-8,13):
		for x in [-3,3]:
			block("Meter marker",Vector3(x,.012,z),Vector3(.18,.018,.045),Color("cba977"))
	signpost("01 / LEVEL\n1 m markers",Vector3(3.8,.7,-3))
	signpost("02 / ARTICULATION\n100 + 200 mm",Vector3(3.5,.8,6))
	signpost("03 / ASCENT\n10 degrees",Vector3(0,2.8,21))
	signpost("04 / CROSS-SLOPE\n10 degrees",Vector3(9,2.3,18))
	signpost("SAND PROXY\nFriction only / no sinkage",Vector3(-10,.8,5))
	signpost("CONSOLIDATED\nRigid regolith proxy",Vector3(9,.8,5))
	var rng := RandomNumberGenerator.new(); rng.seed=7462
	for i in 110:
		var x := rng.randf_range(-70,70); var z := rng.randf_range(-50,70)
		if absf(x)<17 and z>-12 and z<28: continue
		var rock := MeshInstance3D.new(); var stone := SphereMesh.new()
		stone.radial_segments=7; stone.rings=3
		rock.mesh=stone
		rock.position=Vector3(x,0,z)
		rock.scale=Vector3(rng.randf_range(.4,2),rng.randf_range(.2,1.3),rng.randf_range(.4,2))
		rock.material_override=material(Color("684735"))
		add_child(rock)
	for i in 16:
		var mountain := MeshInstance3D.new(); var cone := CylinderMesh.new()
		cone.top_radius=rng.randf_range(1,5); cone.bottom_radius=rng.randf_range(14,25); cone.height=rng.randf_range(10,23); cone.radial_segments=9
		mountain.mesh=cone; mountain.position=Vector3(sin(i*TAU/16)*100,cone.height*.36,cos(i*TAU/16)*100)
		mountain.material_override=material(Color("6a4e40")); add_child(mountain)

func spawn_rover() -> void:
	if is_instance_valid(rover):
		remove_child(rover); rover.queue_free()
	rover=Node3D.new(); rover.set_script(RoverScript)
	rover.name="Curiosity"; rover.spawn_offset=Vector3(0,.045,0)
	add_child(rover)
	if not is_instance_valid(orbit):
		orbit=Node3D.new(); orbit.set_script(CameraScript); add_child(orbit)
	orbit.target=rover.chassis
	orbit.initialized=false
	orbit.reset_view()

func inputs() -> void:
	var bindings := {"forward":[KEY_W,KEY_UP],"reverse":[KEY_S,KEY_DOWN],"left":[KEY_A,KEY_LEFT],"right":[KEY_D,KEY_RIGHT],"brake":[KEY_SPACE],"mode":[KEY_TAB],"overlay":[KEY_F1],"camera_reset":[KEY_C],"reset_rover":[KEY_R],"inspection":[KEY_V],"zoom_in":[KEY_EQUAL],"zoom_out":[KEY_MINUS]}
	for action in bindings:
		if not InputMap.has_action(action): InputMap.add_action(action)
		for key in bindings[action]:
			var e := InputEventKey.new(); e.physical_keycode=key; InputMap.action_add_event(action,e)
	for entry in [["brake",JOY_BUTTON_A],["mode",JOY_BUTTON_Y],["camera_reset",JOY_BUTTON_RIGHT_STICK],["reset_rover",JOY_BUTTON_BACK],["overlay",JOY_BUTTON_START],["inspection",JOY_BUTTON_X],["zoom_in",JOY_BUTTON_RIGHT_SHOULDER],["zoom_out",JOY_BUTTON_LEFT_SHOULDER]]:
		var e := InputEventJoypadButton.new(); e.button_index=entry[1]; InputMap.action_add_event(entry[0],e)

func make_hud() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	var footer := ColorRect.new(); footer.position=Vector2(20,715); footer.size=Vector2(1400,169); footer.color=Color(.025,.035,.045,.77); footer.mouse_filter=Control.MOUSE_FILTER_IGNORE; layer.add_child(footer)
	panel_back=ColorRect.new(); panel_back.position=Vector2(805,82);panel_back.size=Vector2(590,565);panel_back.color=Color(.025,.035,.045,.84);panel_back.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel_back.visible=false;layer.add_child(panel_back)
	var title := Label.new(); title.position=Vector2(34,26); title.text="THE CURIOSITY VOYAGE"; title.add_theme_font_size_override("font_size",26); layer.add_child(title)
	var sub := Label.new(); sub.position=Vector2(36,60); sub.text="MARS  /  MOBILITY FIELD LAB"; sub.modulate=Color("e8b77c"); sub.add_theme_font_size_override("font_size",14); layer.add_child(sub)
	mode_label=Label.new(); mode_label.position=Vector2(36,96); mode_label.add_theme_font_size_override("font_size",16); layer.add_child(mode_label)
	hud=Label.new(); hud.position=Vector2(36,724); hud.add_theme_font_size_override("font_size",23); layer.add_child(hud)
	var controls := Label.new(); controls.position=Vector2(36,805); controls.add_theme_font_size_override("font_size",15)
	controls.text="WASD / arrows  Drive & steer    SPACE  Brake    TAB  Time mode    F1  Engineering\nRight mouse / right stick  Orbit    Wheel  Zoom    C  Camera reset    V  Rover view    R  Recover\nRover visual: NASA/JPL-Caltech  |  Research prototype: estimated actuators, rigid ground contact"
	layer.add_child(controls)
	panel=Label.new(); panel.position=Vector2(825,96); panel.add_theme_font_size_override("font_size",16); panel.visible=false; layer.add_child(panel)

func apply_mode() -> void:
	var factor: float = rover.value("game_time_scale") if accelerated else 1.0
	Engine.time_scale=factor
	Engine.physics_ticks_per_second=int(rover.value("physics_hz")*factor)
	mode_label.text="EXPLORE  /  %.0fx simulation time\nPhysical speed limit 0.040 m/s"%factor if accelerated else "ENGINEERING  /  Real-time Mars\nPhysical speed limit 0.040 m/s"

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("mode"): accelerated=not accelerated; apply_mode()
	if event.is_action_pressed("overlay"): engineering=not engineering; panel.visible=engineering;panel_back.visible=engineering
	if event.is_action_pressed("reset_rover"): spawn_rover()

func _physics_process(_dt: float) -> void:
	var throttle := Input.get_axis("reverse","forward")
	var turn := Input.get_axis("right","left")
	if Input.get_connected_joypads().size()>0 or test_pad>=0:
		var pad := test_pad if test_pad>=0 else Input.get_connected_joypads()[0]
		var stick := Input.get_vector("ui_left","ui_right","ui_up","ui_down")
		stick=Vector2(Input.get_joy_axis(pad,JOY_AXIS_LEFT_X),Input.get_joy_axis(pad,JOY_AXIS_LEFT_Y))
		if stick.length()>.15:
			throttle=-stick.y; turn=-stick.x
	rover.command_v=throttle*rover.value("baseline_speed")
	rover.command_yaw=turn*rover.value("baseline_yaw_rate")
	rover.brake=Input.is_action_pressed("brake")

func _process(dt: float) -> void:
	elapsed+=dt/maxf(Engine.time_scale,.001)
	if elapsed>2 and screenshot_mode: frame_samples.append(dt/maxf(Engine.time_scale,.001)*1000)
	var t: Dictionary = rover.telemetry()
	hud.text="%05.2f cm/s    %03.0f° HEADING\n899 kg   /   3.71 m/s²   /   ARM LOCKED"%[t.speed*100,fposmod(t.heading,360)]
	if engineering:
		panel.text="ENGINEERING TELEMETRY\nPitch %+.2f°    Roll %+.2f°\nDifferential residual %+.3f°\nInferred support %.0f N / 3335 N\n"%[t.pitch,t.roll,t.differential_error_deg,t.support_n]
		for w in t.wheels:
			panel.text+="\n%s  steer %+.1f°   %.3f rad/s\n     %.1f Nm   slip %+.2f   %s"%[w.id,w.steer_deg,w.rate,w.torque,w.slip,"CONTACT" if w.contacts>0 else "AIR"]
		panel.text+="\n\nRigid contact; no soil sinkage\nMast POV is illustrative / arm locked\nFPS %d / draw calls %d"%[Engine.get_frames_per_second(),Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]
	if screenshot_mode and elapsed>8:
		screenshot_mode=false
		capture.call_deferred()

func capture() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://evidence/runtime.png")
	var f := FileAccess.open("res://evidence/performance.json",FileAccess.WRITE)
	frame_samples.sort()
	f.store_string(JSON.stringify({"fps":Engine.get_frames_per_second(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"render_primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"video_adapter":RenderingServer.get_video_adapter_name(),"physics_seconds":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),"median_frame_ms":frame_samples[frame_samples.size()/2],"p95_frame_ms":frame_samples[int(frame_samples.size()*.95)],"frames_sampled":frame_samples.size(),"window_pixels":str(DisplayServer.window_get_size()),"time_scale":Engine.time_scale,"telemetry":rover.telemetry()},"  "))
	get_tree().quit()
