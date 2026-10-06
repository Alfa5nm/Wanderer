extends "res://scripts/world.gd"

var astronaut: MarsAstronaut
var human_control := false
var rover_spawn_local := Vector2.ZERO
var rover_spawn_yaw := 0.0
var scout: ScoutAssessment
var scout_presentation: ScoutPresentation
var recording: MarsRecordingDirector

var result: TerrainPatchResult
var graph: TerrainGenerationGraph
var service: PlanetSurfaceService
var builder: TerrainPatchBuilder
var terrain_root: Node3D
var rock_root: Node3D
var route_mesh: MeshInstance3D
var information: RichTextLabel
var settings_scroll: ScrollContainer
var settings_panel: VBoxContainer
var status: Label
var density: SpinBox
var seed_input: SpinBox
var spacing: OptionButton
var rebuild: Button
var overhead: Camera3D
var initialized_patch := false
var loading: Label
var source_appearance := false
var source_toggle: CheckBox
var detail_quality: OptionButton
var detail: TerrainDetailRenderer
var surface_materials: Array[ShaderMaterial] = []
var rock_material: ShaderMaterial
var gravel_material: ShaderMaterial
var gravel_visual: MultiMeshInstance3D
var patch_lighting: PlanetLighting
var footer_rect: ColorRect
var control_label: Label
var laid_out_size := Vector2.ZERO
var dust: MarsLocalDust
var atmosphere_slider: HSlider
var atmosphere_preset: OptionButton
var close_gravel: MarsCloseGravel
var tracks: MarsWheelTracks
var pace := 6.0
var pace_selector: OptionButton
var graphics_quality: OptionButton

func _ready() -> void:
	accelerated=true
	var payload: Dictionary = get_tree().root.get_meta("terrain_patch_handoff",{})
	if get_tree().root.has_meta("terrain_patch_handoff"): get_tree().root.remove_meta("terrain_patch_handoff")
	builder=TerrainPatchBuilder.new()
	if not payload.is_empty():
		service=payload.service
		service.reparent(self)
		graph=payload.graph
		builder.evaluator=payload.evaluator
	else:
		service=PlanetSurfaceService.new()
		add_child(service)
		graph=TerrainGenerationGraph.standard()
	builder.service=service
	add_child(builder)
	builder.completed.connect(prepared)
	builder.failed.connect(func(message: String):
		if detail!=null: detail.suspended=false
		if status!=null: status.text=message; rebuild.disabled=false
		elif loading!=null: loading.text=message+"\nEscape: return to Mars")
	if not payload.is_empty(): prepared(payload.result)
	else:
		var region = TerrainMissionRegion.new()
		region.title="Bradbury Landing terrain"
		region.origin_radius_m=float(service.sample(region.latitude,region.longitude).radial_m)
		var ui = CanvasLayer.new()
		add_child(ui)
		loading=Label.new()
		loading.position=Vector2(32,32)
		loading.text="Preparing sourced Bradbury terrain…"
		ui.add_child(loading)
		builder.start(graph,region)

func prepared(value: TerrainPatchResult) -> void:
	var previous_hashes: Dictionary = result.hashes.duplicate() if result!=null else {}
	var previous_region: String = result.region.signature() if result!=null else ""
	result=value
	if not initialized_patch:
		initialized_patch=true
		if loading!=null: loading.get_parent().queue_free()
		super._ready()
		configure_lighting()
		overhead=Camera3D.new()
		overhead.projection=Camera3D.PROJECTION_ORTHOGONAL
		overhead.size=maxf(result.region.size_m.x,result.region.size_m.y)*1.15
		overhead.far=2000
		add_child(overhead)
		setup_exploration()
	else:
		if previous_hashes.get("collision","")!=value.hashes.get("collision",""): install_geometry()
		if previous_hashes.get("imagery","")!=value.hashes.get("imagery","") or previous_hashes.get("shading","")!=value.hashes.get("shading",""): apply_material()
		if previous_hashes.get("rocks","")!=value.hashes.get("rocks",""): install_rocks()
		if previous_hashes.get("gravel","")!=value.hashes.get("gravel",""): install_gravel()
		install_route()
		if previous_region!=result.region.signature(): configure_lighting()
	update_appearance()
	if detail!=null: detail.suspended=false
	if information!=null: show_sources()
	if status!=null:
		status.text="Ready · %.0f × %.0f m\nSourced elevation · procedural rocks" % [result.region.size_m.x,result.region.size_m.y]
		if result.route.get("origin","")=="user_planned": status.text+="\nUSER PLANNED PATH · not a historic traverse"
		for warning in result.route.get("warnings",[]): status.text+="\n"+str(warning)
		rebuild.disabled=false
	if recording!=null: recording.patch_ready()

func setup_exploration() -> void:
	if ResourceLoader.exists("res://assets/astronaut/astronaut.glb"):
		astronaut=MarsAstronaut.new(); astronaut.world=self
		astronaut.position=Vector3(-5,result.field.sample(-5,0).height+0.05,0)
		add_child(astronaut)
	else: push_warning("Astronaut asset unavailable; rover exploration remains available.")
	scout=ScoutAssessment.new(); scout.world=self; add_child(scout)
	scout_presentation=ScoutPresentation.new(); scout_presentation.world=self; add_child(scout_presentation)
	recording=MarsRecordingDirector.new(); recording.world=self; add_child(recording)

func switch_actor() -> void:
	if astronaut==null or astronaut.state=="fallen": return
	human_control=not human_control
	astronaut.controlled=human_control
	orbit.set_process(not human_control); orbit.set_process_unhandled_input(not human_control)
	astronaut.camera_rig.enabled=human_control
	if human_control:
		rover.command_v=0; rover.command_yaw=0; rover.brake=true
		astronaut.camera_rig.focus=astronaut.position+Vector3.UP*1.1
		astronaut.camera_rig.camera.current=true
	else: orbit.camera.current=true
	apply_mode()
	if pace_selector!=null: pace_selector.disabled=human_control

func make_terrain() -> void:
	install_geometry()
	install_rocks()
	install_gravel()
	install_route()

func install_geometry() -> void:
	if terrain_root!=null: remove_child(terrain_root); terrain_root.queue_free()
	terrain_root=Node3D.new()
	terrain_root.name="SourcedTerrain"
	add_child(terrain_root)
	var pm = PhysicsMaterial.new()
	pm.friction=0.85
	for chunk in result.chunks:
		var body = StaticBody3D.new()
		body.name="Chunk_%s" % chunk.id
		body.position=chunk.origin
		body.physics_material_override=pm
		body.set_meta("scenery",chunk.get("scenery",false))
		body.set_meta("chunk",chunk)
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,chunk.arrays)
		var visual = MeshInstance3D.new()
		visual.mesh=mesh
		body.add_child(visual)
		var collision = CollisionShape3D.new()
		var shape = ConcavePolygonShape3D.new()
		if not chunk.faces.is_empty():
			shape.set_faces(chunk.faces)
			collision.shape=shape
			body.add_child(collision)
		terrain_root.add_child(body)
	apply_material()
	if detail==null:
		detail=TerrainDetailRenderer.new()
		add_child(detail)
		detail.artifacts.root_path=builder.evaluator.artifacts.root_path
	detail.configure(result,terrain_root)
	var bounds = result.region.playable_bounds()
	for edge in 4:
		var center = Vector2(0,bounds.position.y if edge==0 else bounds.end.y) if edge<2 else Vector2(bounds.position.x if edge==2 else bounds.end.x,0)
		var wall = StaticBody3D.new()
		wall.name="MissionBoundary"
		wall.position=Vector3(center.x,result.field.sample(center.x,center.y).height,center.y)
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size=Vector3(bounds.size.x,1024,0.3) if edge<2 else Vector3(0.3,1024,bounds.size.y)
		collision.shape=shape
		wall.add_child(collision)
		terrain_root.add_child(wall)
	for corner in [bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]:
		var marker = Label3D.new()
		marker.position=Vector3(corner.x,result.field.sample(corner.x,corner.y).height+1,corner.y)
		marker.text="MISSION EDGE"
		marker.font_size=24
		marker.pixel_size=0.025
		marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		terrain_root.add_child(marker)

func apply_material() -> void:
	var surface := ShaderMaterial.new()
	surface.shader=load("res://procedural_terrain/surface.gdshader")
	surface.set_shader_parameter("imagery",ImageTexture.create_from_image(result.image))
	var cavity: Image = result.cavity_image
	if cavity==null:
		cavity=Image.create(1,1,false,Image.FORMAT_RGBA8)
		cavity.fill(Color.BLACK)
	surface.set_shader_parameter("cavity_map",ImageTexture.create_from_image(cavity))
	var bounds: Rect2 = result.region.terrain_bounds()
	surface.set_shader_parameter("terrain_bounds",Vector4(bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y))
	var scenery: ShaderMaterial = surface.duplicate()
	scenery.set_shader_parameter("imagery",ImageTexture.create_from_image(result.scenery_image))
	surface_materials=[surface,scenery]
	for body in terrain_root.get_children():
		for child in body.get_children():
			if child is MeshInstance3D: child.material_override=scenery if body.get_meta("scenery",false) else surface
	update_appearance()

func update_appearance() -> void:
	for material in surface_materials: graph.surface_style.apply(material,source_appearance)
	if rock_material!=null:
		rock_material.set_shader_parameter("rock_detail",load("res://planetary_map/visuals/assets/rock_normal_roughness.png"))
		rock_material.set_shader_parameter("cinematic",not source_appearance)
		rock_material.set_shader_parameter("cosmetic_seed",float(graph.surface_style.seed%10007))
	if gravel_visual!=null: gravel_visual.visible=not source_appearance
	if gravel_material!=null:
		gravel_material.set_shader_parameter("cosmetic_seed",float(graph.surface_style.seed%10007))
		gravel_material.set_shader_parameter("rock_detail",load("res://planetary_map/visuals/assets/rock_normal_roughness.png"))
	if source_toggle!=null: source_toggle.set_pressed_no_signal(source_appearance)
	if tracks!=null: tracks.bind_materials()

func apply_mode() -> void:
	var factor := pace if accelerated and not human_control else 1.0
	Engine.time_scale=factor
	Engine.physics_ticks_per_second=int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second",120)) if human_control else int(rover.value("physics_hz")*factor)
	if mode_label!=null: mode_label.text="%.0fx simulation · authentic rover physics" % factor

func set_source_appearance(enabled: bool) -> void:
	source_appearance=enabled
	update_appearance()

func install_gravel() -> void:
	if gravel_visual!=null: gravel_visual.queue_free()
	gravel_visual=MultiMeshInstance3D.new()
	gravel_visual.name="IllustrativeGravel"
	var pebble := SphereMesh.new()
	pebble.radius=1; pebble.height=2; pebble.radial_segments=6; pebble.rings=2
	var multimesh := MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_3D
	multimesh.mesh=pebble
	multimesh.instance_count=result.gravel.size()
	for i in result.gravel.size():
		var stone: Dictionary = result.gravel[i]
		var shape: Vector3 = stone.shape*stone.size
		var basis := Basis(Vector3.UP,stone.rotation).scaled(shape)
		multimesh.set_instance_transform(i,Transform3D(basis,stone.position+Vector3.UP*shape.y*0.5))
	gravel_visual.multimesh=multimesh
	gravel_material=ShaderMaterial.new()
	gravel_material.shader=load("res://procedural_terrain/rock.gdshader")
	gravel_material.set_shader_parameter("gravel",true)
	gravel_visual.material_override=gravel_material
	gravel_visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(gravel_visual)
	if close_gravel!=null: close_gravel.queue_free()
	close_gravel=MarsCloseGravel.new()
	close_gravel.world=self
	add_child(close_gravel)
	update_appearance()

func install_rocks() -> void:
	if rock_root!=null: remove_child(rock_root); rock_root.queue_free()
	rock_root=Node3D.new()
	rock_root.name="ProceduralRocks"
	add_child(rock_root)
	var stone = SphereMesh.new()
	stone.radius=1; stone.height=2; stone.radial_segments=8; stone.rings=4
	var stone_arrays: Array = stone.get_mesh_arrays()
	var vertices: PackedVector3Array = stone_arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		var point := vertices[i]
		vertices[i]*=0.94+0.10*sin(point.x*17+point.y*11+point.z*13)
	stone_arrays[Mesh.ARRAY_VERTEX]=vertices
	# Recompute normals for the perturbed silhouette; keep collision vertices identical.
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	var indices: PackedInt32Array = stone_arrays[Mesh.ARRAY_INDEX]
	for triangle in range(0,indices.size(),3):
		var a := indices[triangle]; var b := indices[triangle+1]; var c := indices[triangle+2]
		var normal := (vertices[c]-vertices[a]).cross(vertices[b]-vertices[a])
		normals[a]+=normal; normals[b]+=normal; normals[c]+=normal
	for i in normals.size(): normals[i]=normals[i].normalized()
	stone_arrays[Mesh.ARRAY_NORMAL]=normals
	var prototype := ArrayMesh.new()
	prototype.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,stone_arrays)
	rock_material=ShaderMaterial.new()
	rock_material.shader=load("res://procedural_terrain/rock.gdshader")
	for rock in result.rocks:
		var body = StaticBody3D.new()
		body.position=rock.position+Vector3.UP*rock.size*0.65
		var visual = MeshInstance3D.new()
		var dimensions: Vector3 = rock.shape*rock.size
		body.basis=Basis(Quaternion(Vector3.UP,result.field.normal(rock.position.x,rock.position.z)))*Basis(Vector3.UP,rock.rotation)
		visual.mesh=prototype
		visual.scale=dimensions
		visual.material_override=rock_material
		body.add_child(visual)
		var collision = CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for point in vertices: points.append(point*dimensions)
		shape.points=points
		collision.shape=shape
		body.add_child(collision)
		rock_root.add_child(body)

func install_route() -> void:
	if route_mesh!=null: route_mesh.queue_free(); route_mesh=null
	if result.route.get("arrays",[]).is_empty(): return
	var arrays: Array = result.route.arrays
	if arrays[Mesh.ARRAY_VERTEX].is_empty(): return
	route_mesh=MeshInstance3D.new()
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	route_mesh.mesh=mesh
	var route_material = ShaderMaterial.new()
	route_material.shader=load("res://procedural_terrain/route.gdshader")
	route_mesh.material_override=route_material
	add_child(route_mesh)

func spawn_rover() -> void:
	if is_instance_valid(rover): remove_child(rover); rover.queue_free()
	rover=Node3D.new()
	rover.set_script(RoverScript)
	rover.name="Curiosity"
	rover.spawn_basis=Basis(Quaternion(Vector3.UP,result.field.normal(rover_spawn_local.x,rover_spawn_local.y)))*Basis(Vector3.UP,rover_spawn_yaw)
	rover.spawn_offset=Vector3(rover_spawn_local.x,result.field.sample(rover_spawn_local.x,rover_spawn_local.y).height+0.08,rover_spawn_local.y)
	add_child(rover)
	if not is_instance_valid(orbit): orbit=Node3D.new(); orbit.set_script(CameraScript); add_child(orbit)
	orbit.camera.far=30000
	orbit.target=rover.chassis
	orbit.initialized=false
	orbit.reset_view()
	if tracks!=null: tracks.queue_free()
	tracks=MarsWheelTracks.new()
	tracks.world=self
	add_child(tracks)

func configure_lighting() -> void:
	if patch_lighting!=null: remove_child(patch_lighting); patch_lighting.queue_free()
	if dust!=null: remove_child(dust); dust.queue_free()
	for child in get_children():
		if child is WorldEnvironment or child is DirectionalLight3D: remove_child(child); child.queue_free()
	var settings = PlanetVisualSettings.new()
	var axes = result.region.axes()
	settings.sun_direction=Vector3(settings.sun_direction.dot(axes[0]),settings.sun_direction.dot(axes[1]),-settings.sun_direction.dot(axes[2])).normalized()
	var lighting = PlanetLighting.new()
	lighting.settings=settings
	add_child(lighting)
	patch_lighting=lighting
	lighting.configure_surface(result.region.origin_radius_m-service.physical_radius_m)
	lighting.sun.directional_shadow_max_distance=120
	lighting.sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	lighting.sun.directional_shadow_blend_splits=true
	lighting.sun.shadow_bias=0.12
	lighting.sun.shadow_normal_bias=2.0
	lighting.sun.light_angular_distance=0.35
	lighting.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	lighting.environment.tonemap_exposure=0.9
	set_sun_direction(settings.sun_direction)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	dust=MarsLocalDust.new()
	dust.world=self
	dust.atmosphere=settings.atmosphere
	add_child(dust)
	if atmosphere_slider!=null: atmosphere_slider.set_value_no_signal(settings.atmosphere.strength)
	if graphics_quality!=null: graphics_quality.select(settings.atmosphere.quality)

func set_sun_direction(direction: Vector3) -> void:
	if patch_lighting==null or not direction.is_finite() or direction.length_squared()<0.0001: return
	patch_lighting.set_direction(direction)

func set_atmosphere_strength(value: float) -> void:
	if patch_lighting==null or not is_finite(value): return
	patch_lighting.settings.atmosphere.strength=clampf(value,0,3)
	patch_lighting.update_atmosphere()
	if atmosphere_slider!=null: atmosphere_slider.set_value_no_signal(value)
	get_tree().root.set_meta("mars_appearance",{"strength":patch_lighting.settings.atmosphere.strength,"quality":patch_lighting.settings.atmosphere.quality})

func set_graphics_quality(index: int) -> void:
	patch_lighting.settings.atmosphere.quality=clampi(index,0,2)
	patch_lighting.update_atmosphere()
	if detail!=null: detail.set_quality(index)
	if detail_quality!=null: detail_quality.select(index)
	get_tree().root.set_meta("mars_appearance",{"strength":patch_lighting.settings.atmosphere.strength,"quality":patch_lighting.settings.atmosphere.quality})

func make_hud() -> void:
	super.make_hud()
	mode_label.visible=false
	hud.add_theme_font_size_override("font_size",17)
	for child in get_children():
		if child is CanvasLayer:
			for label in child.get_children():
				if label is ColorRect and label!=panel_back: footer_rect=label
				if label is Label and label.text.begins_with("WASD"): control_label=label
				if label is Label and label.text=="MARS  /  MOBILITY FIELD LAB": label.text="MARS  /  "+result.region.title.to_upper()
	var layer = CanvasLayer.new()
	add_child(layer)
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var box = PanelContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.position=Vector2(-380,120)
	box.custom_minimum_size.x=350
	root.add_child(box)
	var style = StyleBoxFlat.new()
	style.bg_color=Color(0.025,0.03,0.035,0.92)
	style.content_margin_left=12
	style.content_margin_right=12
	style.content_margin_top=12
	style.content_margin_bottom=12
	box.add_theme_stylebox_override("panel",style)
	var column = VBoxContainer.new()
	box.add_child(column)
	status=Label.new()
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x=326
	column.add_child(status)
	var help = Label.new()
	help.text="Shift + click: plan a local path\nT: overhead / rover view · Escape: Mars\nTint, grains, rocks and tracks are illustrative."
	help.add_theme_font_size_override("font_size",12)
	column.add_child(help)
	var toggle = Button.new()
	toggle.text="TERRAIN SETTINGS & SOURCES"
	column.add_child(toggle)
	settings_scroll=ScrollContainer.new()
	settings_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(settings_scroll)
	settings_panel=VBoxContainer.new()
	settings_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(settings_panel)
	settings_panel.visible=false
	settings_scroll.visible=false
	toggle.pressed.connect(func():
		settings_panel.visible=not settings_panel.visible
		settings_scroll.visible=settings_panel.visible)
	pace_selector=OptionButton.new()
	for label in ["Time · 1x engineering", "Time · 6x exploration", "Time · 12x fast travel"]: pace_selector.add_item(label)
	pace_selector.select(1)
	pace_selector.item_selected.connect(func(index: int):
		pace=[1.0,6.0,12.0][index]
		accelerated=pace>1.0
		apply_mode())
	settings_panel.add_child(pace_selector)
	source_toggle=CheckBox.new()
	source_toggle.text="SOURCE APPEARANCE · no cosmetic styling"
	source_toggle.add_theme_font_size_override("font_size",12)
	source_toggle.toggled.connect(set_source_appearance)
	settings_panel.add_child(source_toggle)
	var atmosphere_label := Label.new()
	atmosphere_label.text="ATMOSPHERE · illustrative dust"
	settings_panel.add_child(atmosphere_label)
	atmosphere_preset=OptionButton.new()
	atmosphere_preset.add_item("Dramatic dusty")
	atmosphere_preset.add_item("Clear inspection")
	atmosphere_preset.item_selected.connect(func(index: int): set_atmosphere_strength(1.35 if index==0 else 0.45))
	settings_panel.add_child(atmosphere_preset)
	atmosphere_slider=HSlider.new()
	atmosphere_slider.min_value=0; atmosphere_slider.max_value=3; atmosphere_slider.step=0.05
	atmosphere_slider.value=1.35
	atmosphere_slider.value_changed.connect(set_atmosphere_strength)
	settings_panel.add_child(atmosphere_slider)
	graphics_quality=OptionButton.new()
	for label in ["Graphics · performance", "Graphics · balanced", "Graphics · high"]: graphics_quality.add_item(label)
	graphics_quality.select(1)
	graphics_quality.item_selected.connect(set_graphics_quality)
	settings_panel.add_child(graphics_quality)
	if RenderingServer.get_current_rendering_method()=="forward_plus":
		var native_fog := CheckBox.new()
		native_fog.text="FORWARD+ · native volumetric dust"
		native_fog.button_pressed=true
		native_fog.toggled.connect(func(enabled: bool):
			if patch_lighting!=null: patch_lighting.set_native_fog(enabled))
		settings_panel.add_child(native_fog)
	detail_quality=OptionButton.new()
	for label in ["Detail · performance (3 px)","Detail · balanced (2 px)","Detail · high (1 px)"]: detail_quality.add_item(label)
	detail_quality.select(1)
	detail_quality.item_selected.connect(func(index: int):
		if detail!=null: detail.set_quality(index))
	settings_panel.add_child(detail_quality)
	density=spin(settings_panel,"Rock density / m²",0,0.002,0.0001,float(graph.node("rocks").parameters.density))
	seed_input=spin(settings_panel,"Procedural seed",0,2147483647,1,int(graph.node("rocks").parameters.seed))
	spacing=OptionButton.new()
	for metres in [2,4,8,16]: spacing.add_item("Collision/base sampling · %d m" % metres,metres)
	spacing.select(1)
	settings_panel.add_child(spacing)
	rebuild=Button.new()
	rebuild.text="APPLY SETTINGS"
	settings_panel.add_child(rebuild)
	rebuild.pressed.connect(apply_settings)
	information=RichTextLabel.new()
	information.bbcode_enabled=true
	information.custom_minimum_size=Vector2(326,160)
	information.meta_clicked.connect(func(url): OS.shell_open(str(url)))
	settings_panel.add_child(information)
	var back = Button.new()
	back.text="RETURN TO MARS"
	column.add_child(back)
	back.pressed.connect(return_to_mars)

func spin(parent: Node,title: String,minimum: float,maximum: float,step: float,value: float) -> SpinBox:
	var label = Label.new()
	label.text=title
	parent.add_child(label)
	var control = SpinBox.new()
	control.min_value=minimum; control.max_value=maximum; control.step=step; control.value=value
	parent.add_child(control)
	return control

func show_sources() -> void:
	var text = "[color=#edc395]SOURCE INFORMATION[/color]\n"+result.region.tile_id+"\nLocal +X east / -Z north; metres\nTerrain collar: %.0f m\n" % result.region.collar_m
	for source in result.sources: text+="%s · %.2f m sampling\n" % [source,result.sources[source]]
	text+="Visual mesh: adaptive 1–16 m; collision stays fixed.\nMesh spacing is interpolation, not measured resolution.\n"
	for source in result.elevation_sources:
		text+="[url=%s]%s[/url]\n%s · %s\n%s\nDates: %s\n" % [source.url,source.title,source.product,source.datum,source.accuracy,", ".join(source.dates)]
	text+="[url=https://pds-geosciences.wustl.edu/missions/mgs/megdr.html]MOLA product definitions[/url]\n"
	for source in result.image_sources:
		text+="[url=%s]%s[/url] · %.2f m prepared / %.2f m source\n%s\n%s\nDates: %s\n" % [source.url,source.title,source.spacing_m,source.source_spacing_m,source.classification,source.accuracy,", ".join(source.dates)]
	text+="MOLA fills regional elevation gaps. Global Viking imagery fills image gaps.\nRocks, roughness and friction are model assumptions."
	text+="\nGENERATION INSPECTOR\nRebuilt outputs: "+", ".join(result.evaluated)+"\nReused outputs: "+", ".join(result.cache_hits)+"\nDisk cache: "+", ".join(result.disk_hits)+"\nHue, normals, gravel and rocks: illustrative\nCavity: derived from measured elevation\nOuter scenery: sourced, outside driving bounds"
	text+="\nSky, haze and drifting/wheel dust: illustrative weather, not observations.\nRenderer-specific shared atmosphere; native volumetric dust only in the optional Forward+ trial."
	information.text=text

func apply_settings() -> void:
	graph.node("rocks").parameters.seed=int(seed_input.value)
	graph.node("rocks").parameters.density=density.value
	graph.node("grid").parameters.spacing_m=spacing.get_selected_id()
	graph.surface_style.seed=int(seed_input.value)
	if graph.node("gravel")!=null: graph.node("gravel").parameters.seed=int(seed_input.value)
	update_appearance()
	start_rebuild()

func start_rebuild() -> void:
	if builder.busy: return
	if detail!=null: detail.suspended=true
	rebuild.disabled=true
	status.text="Preparing changes… existing terrain stays available."
	if not builder.start(graph,result.region):
		rebuild.disabled=false; status.text="Unable to prepare terrain changes"
		if detail!=null: detail.suspended=false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE: return_to_mars(); return
	if not initialized_patch: return
	if (event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_H) or (event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_DPAD_UP):
		switch_actor(); return
	if human_control and event.is_action_pressed("reset_rover"):
		astronaut.recover(); return
	if human_control and event.is_action_pressed("mode"): return
	super._input(event)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_T:
		if overhead.current: orbit.camera.current=true
		else:
			overhead.position=Vector3(0,result.field.sample(0,0).height+500,0)
			overhead.look_at(Vector3(0,result.field.sample(0,0).height,0),Vector3.FORWARD)
			overhead.current=true
	if event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_B: return_to_mars()

func _unhandled_input(event: InputEvent) -> void:
	if not initialized_patch or builder.busy: return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and event.shift_pressed:
		var camera: Camera3D = get_viewport().get_camera_3d()
		var ray = PhysicsRayQueryParameters3D.create(camera.project_ray_origin(event.position),camera.project_ray_origin(event.position)+camera.project_ray_normal(event.position)*2000,1)
		var hit = get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or not result.region.playable_bounds().has_point(Vector2(hit.position.x,hit.position.z)): return
		var active: Node3D = astronaut if human_control else rover.chassis
		scout.propose(Vector2(active.global_position.x,active.global_position.z),Vector2(hit.position.x,hit.position.z))
		status.text="UNVERIFIED PROPOSAL · scout before walking"

func _process(dt: float) -> void:
	if initialized_patch:
		super._process(dt)
		var telemetry: Dictionary = rover.telemetry()
		hud.text="%.2f cm/s  ·  %03.0f°  ·  %.0fx time  ·  F1 telemetry" % [telemetry.speed*100*Engine.time_scale,fposmod(telemetry.heading,360),Engine.time_scale]
		if human_control: hud.text="ASTRONAUT · %.2f m/s · Mars-inspired movement · 1x time" % Vector2(astronaut.velocity.x,astronaut.velocity.z).length()
		if settings_scroll!=null: settings_scroll.custom_minimum_size.y=clampf(get_viewport().get_visible_rect().size.y-490,160,300) if settings_panel.visible else 0
		var size: Vector2 = get_viewport().get_visible_rect().size
		if size!=laid_out_size:
			laid_out_size=size
			if footer_rect!=null: footer_rect.position=Vector2(20,size.y-83); footer_rect.size=Vector2(size.x-40,67); footer_rect.color.a=0.66
			if control_label!=null:
				control_label.position=Vector2(36,size.y-51)
				control_label.add_theme_font_size_override("font_size",12)
				control_label.text="H Human / Rover   F9 Capture   WASD Move   SPACE Brake / Brace   RMB Orbit   WHEEL Zoom   C Reset view   V Rover view   T Overhead   TAB Time   R Recover   ESC Mars"
			hud.position=Vector2(36,size.y-77)
			panel_back.position.x=size.x-635; panel.position.x=size.x-615
		if detail!=null: detail.camera=get_viewport().get_camera_3d()

func _physics_process(dt: float) -> void:
	if initialized_patch:
		if human_control: rover.command_v=0; rover.command_yaw=0; rover.brake=true
		else: super._physics_process(dt)

func return_to_mars() -> void:
	builder.cancel()
	Engine.time_scale=1
	Engine.physics_ticks_per_second=int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second",120))
	get_tree().change_scene_to_file("res://planetary_map/mars_globe.tscn")
