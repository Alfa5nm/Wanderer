class_name MarsRecordingDirector
extends Node

const SHOTS := ["OVERHEAD MAP","ENTER THE MAP","PROGRESSIVE TERRAIN","DATA → DECISION","PROVENANCE","SCOUT → HUMAN"]
var world: Node
var camera: Camera3D
var layer: CanvasLayer
var panel: VBoxContainer
var title: Label
var provenance: RichTextLabel
var enabled := false
var shot := -1
var stage := 0
var tween: Tween
var worker: Thread
var scenario: Dictionary = {}
var risk: Texture2D
var hud_hidden := false
var awaiting_region := false
var destination_labels: Array[Label3D] = []
var servo: AudioStreamPlayer

func _ready() -> void:
	camera=Camera3D.new(); camera.name="RecordingCamera"; camera.near=0.08; camera.far=30000
	world.add_child(camera)
	layer=CanvasLayer.new(); layer.layer=15; add_child(layer)
	panel=VBoxContainer.new(); panel.position=Vector2(24,470); layer.add_child(panel)
	var heading := Label.new(); heading.text="CAPTURE PRESETS · F9 toggle · F8 HUD · F10 reset"; panel.add_child(heading)
	for i in SHOTS.size():
		var button := Button.new(); button.text="%d · %s" % [i+1,SHOTS[i]]
		button.pressed.connect(select_shot.bind(i)); panel.add_child(button)
	var prepare := Button.new(); prepare.text="PREPARE REPEATABLE SCOUT SCENARIO"
	prepare.pressed.connect(prepare_scenario); panel.add_child(prepare)
	var slope := Button.new(); slope.text="SHOW SLOPE ASSESSMENT"
	slope.pressed.connect(func(): set_stage(3)); panel.add_child(slope)
	title=Label.new(); title.position=Vector2(32,88); title.add_theme_font_size_override("font_size",18); layer.add_child(title)
	provenance=RichTextLabel.new(); provenance.position=Vector2(24,130); provenance.size=Vector2(440,290)
	provenance.bbcode_enabled=true; provenance.add_theme_font_size_override("normal_font_size",16)
	provenance.meta_clicked.connect(func(url): OS.shell_open(str(url))); layer.add_child(provenance)
	var card := StyleBoxFlat.new(); card.bg_color=Color(0.02,0.025,0.03,0.92)
	card.content_margin_left=12; card.content_margin_top=12; card.content_margin_right=12
	provenance.add_theme_stylebox_override("normal",card)
	panel.hide(); title.hide(); provenance.hide()
	servo=AudioStreamPlayer.new(); servo.stream=load("res://capture/servo.wav"); servo.volume_db=-17; add_child(servo)
	world.builder.failed.connect(func(message: String):
		awaiting_region=false; scenario["ready"]=false
		title.show(); title.text="Scenario preparation failed; current patch retained. "+message)
	world.scout.route_ready.connect(func(route: Dictionary):
		if route.has("risk_map"): install_risk(route.risk_map,route.risk_bounds)
		if enabled and shot==5: title.text="SCOUT → MAP UPDATE → "+route.state.to_upper()+" → H: HUMAN")

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode==KEY_F9:
		enabled=not enabled; panel.visible=enabled; title.visible=enabled
		if not enabled:
			if tween!=null: tween.kill()
			set_stage(0); provenance.hide(); show_hud(true)
			if world.human_control: world.astronaut.camera_rig.camera.current=true
			else: world.orbit.camera.current=true
	if not enabled: return
	if event.keycode>=KEY_1 and event.keycode<=KEY_6: select_shot(event.keycode-KEY_1)
	if event.keycode==KEY_F8: show_hud(hud_hidden)
	if event.keycode==KEY_F10: reset_scenario()

func show_hud(show: bool) -> void:
	hud_hidden=not show
	for node in world.find_children("*","CanvasLayer",true,false):
		if node!=layer: node.visible=show
	panel.visible=show and enabled

func set_stage(value: int) -> void:
	stage=value
	for mesh in world.rover.find_children("*","MeshInstance3D",true,false): mesh.visible=stage==0
	if world.astronaut!=null: world.astronaut.model.visible=stage==0
	for material in world.surface_materials:
		material.set_shader_parameter("presentation_mode",stage)
	if world.tracks!=null and world.tracks.material!=null: world.tracks.material.set_shader_parameter("presentation_mode",stage)
	world.rock_root.visible=stage==0
	world.gravel_visual.visible=stage==0 and not world.source_appearance
	world.close_gravel.visible=stage==0 and not world.source_appearance

func select_shot(index: int) -> void:
	enabled=true; title.show(); shot=index
	show_hud(false)
	if tween!=null: tween.kill()
	provenance.hide(); set_stage(0)
	for label in destination_labels: label.queue_free()
	destination_labels.clear()
	var focus: Vector3 = world.rover.chassis.position+Vector3.UP*0.6
	title.text=SHOTS[index]+" · SOURCED TERRAIN / ILLUSTRATIVE EXPLORATION"
	match index:
		0:
			camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=80
			camera.position=focus+Vector3(0,160,0); camera.look_at(focus,Vector3.FORWARD); camera.current=true
			set_stage(2)
		1:
			camera.projection=Camera3D.PROJECTION_PERSPECTIVE; camera.fov=54; camera.current=true
			tween=create_tween().set_ignore_time_scale(true)
			tween.tween_method(func(t: float):
				camera.position=focus+Vector3(-4*t,lerpf(85,2.3,t),-6*t)
				camera.look_at(focus,Vector3.FORWARD if t<0.01 else Vector3.UP),0.0,1.0,4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		2:
			camera.projection=Camera3D.PROJECTION_PERSPECTIVE; camera.position=focus+Vector3(-15,8,-20); camera.look_at(focus); camera.current=true
			set_stage(1)
			world.detail.set_quality(0)
			tween=create_tween().set_ignore_time_scale(true)
			tween.tween_interval(2.0); tween.tween_callback(func(): world.detail.set_quality(2); set_stage(0))
		3:
			camera.projection=Camera3D.PROJECTION_PERSPECTIVE; camera.position=focus+Vector3(-12,6,-16); camera.look_at(focus); camera.current=true
			set_stage(1)
			tween=create_tween().set_ignore_time_scale(true)
			tween.tween_interval(3.0); tween.tween_callback(func(): set_stage(2); title.text="REGISTERED ORBITAL IMAGERY → SURFACE")
			tween.tween_interval(3.0); tween.tween_callback(func(): set_stage(3); title.text="DERIVED SLOPE → PLANNING COST · MODEL THRESHOLDS")
			tween.tween_interval(3.0); tween.tween_callback(show_destinations)
		4:
			world.orbit.camera.current=true; provenance.show()
			var text := "[color=#edc395]NASA DATA → THIS TERRAIN[/color]\n"
			var sources: Array = world.result.elevation_sources.duplicate()
			sources.sort_custom(func(a,b): return a.source_spacing_m<b.source_spacing_m)
			for source in sources.slice(0,1):
				text+="%s\n%s\n%.2f m source / %.2f m prepared\n%s\n[url=%s]Open source record[/url]\n\n" % [source.title,source.product,source.source_spacing_m,source.spacing_m,source.accuracy,source.url]
			text+="Registered imagery: "+(world.result.image_sources[0].title if not world.result.image_sources.is_empty() else "Global Viking fallback")+"\nCoverage: valid regional pixels; MOLA/Viking fill gaps.\nDates: "+(", ".join(world.result.elevation_sources[0].dates) if not world.result.elevation_sources.is_empty() else "Not documented")+"\nHue, gravel, suit motion and dust are illustrative."
			provenance.text=text
		5:
			world.orbit.camera.current=true; show_hud(false); servo.play()
			title.text="ROVER SCOUTING · "+scenario.get("kind","DERIVED ASSESSMENT")+" · H: HUMAN CONTROL"
			world.scout_presentation.map.get_parent().visible=true
			world.scout_presentation.map.show(); world.scout_presentation.notice.show()

func prepare_scenario() -> void:
	if worker!=null: return
	title.show(); title.text="Preparing measured-slope scenario; checking alternatives…"
	var field := TerrainHeightField.new(); field.region=world.result.region; field.service=world.service
	worker=Thread.new()
	if worker.start(ScoutScenario.find.bind({"field":field,"rocks":world.result.rocks.duplicate(true)}))!=OK:
		worker=null; title.text="Preparation worker unavailable; existing terrain remains ready."

func install_risk(image: Image,bounds: Rect2) -> void:
	risk=ImageTexture.create_from_image(image)
	for material in world.surface_materials:
		material.set_shader_parameter("slope_map",risk)
		material.set_shader_parameter("slope_bounds",Vector4(bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y))
		material.set_shader_parameter("has_slope_map",true)
	if world.tracks!=null and world.tracks.material!=null:
		world.tracks.material.set_shader_parameter("slope_map",risk)
		world.tracks.material.set_shader_parameter("slope_bounds",Vector4(bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y))
		world.tracks.material.set_shader_parameter("has_slope_map",true)

func show_destinations() -> void:
	set_stage(2)
	title.text="SCIENCE AREA → DESTINATION · ARCHIVED ROVER POSITIONS"
	for site in PlanetScienceSite.curated():
		var point: Vector2 = world.result.region.local_from_geographic(site.latitude,site.longitude)
		if point.length()>20000: continue
		var marker := Label3D.new(); marker.text=site.title+"\nRover localization · exact sample offset unknown"
		marker.position=Vector3(point.x,world.result.field.sample(point.x,point.y).height+1,point.y)
		marker.font_size=24; marker.pixel_size=0.01; marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		world.add_child(marker); destination_labels.append(marker)
		if point.length()<world.result.region.size_m.length():
			camera.position=marker.position+Vector3(-9,5,-12); camera.look_at(marker.position); camera.current=true

func _process(_delta: float) -> void:
	panel.position.y=clampf(world.get_viewport().get_visible_rect().size.y-340,140,470)
	if worker!=null and not worker.is_alive():
		scenario=worker.wait_to_finish(); worker=null
		install_risk(scenario.risk_map,scenario.risk_bounds)
		if scenario.ready:
			if scenario.has("region") and scenario.region.signature()!=world.result.region.signature():
				awaiting_region=true
				title.text="Preparing sourced Gale slope patch…"
				if not world.builder.start(world.graph,scenario.region):
					awaiting_region=false; title.text="Patch preparation unavailable; current terrain retained."
			else: reset_scenario()
		else: title.text=scenario.message

func reset_scenario() -> void:
	if not scenario.get("ready",false): prepare_scenario(); return
	if world.human_control: world.switch_actor()
	if tween!=null: tween.kill()
	set_stage(0); provenance.hide(); shot=-1
	world.scout.reset()
	world.rover_spawn_local=scenario.start
	var delta: Vector2 = scenario.goal-scenario.start
	world.rover_spawn_yaw=atan2(delta.x,delta.y)
	world.spawn_rover()
	var stage: Vector2 = scenario.start+Vector2(-delta.y,delta.x).normalized()*3
	if world.astronaut!=null: world.astronaut.respawn(Vector3(stage.x,world.result.field.sample(stage.x,stage.y).height+0.05,stage.y))
	world.orbit.camera.current=true
	if world.astronaut!=null:
		world.astronaut.camera_rig.yaw=world.rover_spawn_yaw-0.55
		world.astronaut.camera_rig.pitch=0.3; world.astronaut.camera_rig.distance=4.5
	world.scout.propose(stage,scenario.goal)
	title.show(); title.text="READY · "+scenario.kind+" · drive to inspect, then H to walk"

func _exit_tree() -> void:
	if worker!=null: worker.wait_to_finish()

func patch_ready() -> void:
	if not awaiting_region: return
	awaiting_region=false
	world.scout.generation+=1
	world.scout.field=TerrainHeightField.new(); world.scout.field.region=world.result.region; world.scout.field.service=world.service
	world.scout_presentation.map.image=ImageTexture.create_from_image(world.result.image)
	install_risk(scenario.risk_map,scenario.risk_bounds)
	reset_scenario()
