extends Node3D

signal navigation_changed(state: int)
enum Navigation { PLANET_VIEW, REGION_FOCUS, MISSION_FOCUS, SURFACE_APPROACH, DEPLOYMENT_TRANSITION }
@export var definition: PlanetDefinition
@export var visual_settings := PlanetVisualSettings.new()
var state := Navigation.PLANET_VIEW
var history: Array[Dictionary] = []
var planet: Node3D
var surface: MeshInstance3D
var terrain: PlanetTerrainRenderer
var surface_service: PlanetSurfaceService
var streamer: PlanetTileStreamer
var survey: PlanetSurveyGrid
var cell_panel: PanelContainer
var cell_text: RichTextLabel
var grid_toggle: CheckButton
var cell_open := false
var rig: PlanetCameraRig
var layer_manager: PlanetLayerManager
var markers: PlanetMarkerManager
var selection: PlanetSelection
var hud: PlanetHUD
var deployment: PlanetDeployment
var routes: PlanetRouteRenderer
var region: PlanetRegion
var mission: PlanetMission
var site: PlanetMissionSite
var selected_id := ""
var refresh_clock := 0.0
var dirty := true
var previous_aspect: int
var sun: DirectionalLight3D
var patch_builder: TerrainPatchBuilder
var patch_graph: TerrainGenerationGraph
var patch_building := false
var lighting: PlanetLighting

func _ready() -> void:
	previous_aspect = get_window().content_scale_aspect
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second",120))
	if definition == null:
		push_error("Planet definition missing")
		definition = PlanetDefinition.new()
	if not is_finite(definition.radius) or definition.radius <= 0:
		push_warning("Invalid planet radius; using normalized sphere")
		definition.radius = 1.0
	definition=definition.duplicate(true)
	for science_site in PlanetScienceSite.curated(): definition.markers.append(science_site)
	lighting=PlanetLighting.new()
	lighting.settings=visual_settings
	add_child(lighting)
	sun=lighting.sun
	planet = Node3D.new()
	planet.name = "PlanetGeometry"
	planet.scale = Vector3.ONE*PlanetCameraRig.RENDER_SCALE
	add_child(planet)
	surface = MeshInstance3D.new()
	surface_service = PlanetSurfaceService.new()
	surface_service.radius = definition.radius
	surface_service.physical_radius_m = definition.physical_radius_km*1000
	add_child(surface_service)
	surface.mesh = null
	planet.add_child(surface)
	layer_manager = PlanetLayerManager.new()
	layer_manager.surface = surface
	add_child(layer_manager)
	for layer in definition.layers: layer_manager.register_layer(layer)
	if not layer_manager.set_view_mode("visual"):
		var fallback := PlanetDataLayer.new()
		layer_manager.register_layer(fallback)
		layer_manager.set_view_mode("visual")
	rig = PlanetCameraRig.new()
	rig.radius = definition.radius
	add_child(rig)
	rig.surface_service = surface_service
	rig.min_distance = definition.radius*1.000025
	rig.moved.connect(func(): dirty = true; planet.position=rig.position)
	rig.update_camera()
	terrain = PlanetTerrainRenderer.new()
	terrain.service = surface_service
	terrain.camera = rig.camera
	terrain.visual_settings = lighting.settings
	planet.add_child(terrain)
	rig.moved.connect(terrain.sync_view)
	lighting.configure(rig,terrain)
	layer_manager.layer_changed.connect(func(_id: String): terrain.set_albedo(surface.material_override.albedo_texture))
	streamer = PlanetTileStreamer.new()
	streamer.service = surface_service
	streamer.rig = rig
	add_child(streamer)
	survey = PlanetSurveyGrid.new()
	survey.service = surface_service
	survey.rig = rig
	planet.add_child(survey)
	var ui := CanvasLayer.new()
	add_child(ui)
	markers = PlanetMarkerManager.new()
	ui.add_child(markers)
	markers.surface_service = surface_service
	markers.configure(definition,planet,rig.camera)
	hud = PlanetHUD.new()
	hud.wait_for_terrain = true
	ui.add_child(hud)
	terrain.boot_ready.connect(hud.begin_boot_fade)
	if terrain.roots_ready: hud.begin_boot_fade()
	hud.heading.text = definition.title
	build_survey_ui()
	var scout_overlay := ScoutGlobeOverlay.new(); scout_overlay.globe=self; add_child(scout_overlay)
	survey.cell_selected.connect(show_cell)
	streamer.status_changed.connect(stream_status)
	for data in definition.markers:
		if data == null or not data.is_valid(): continue
		if data is PlanetRegion and region == null: region = data
		if data is PlanetMission and mission == null: mission = data
		if data is PlanetMissionSite and site == null: site = data
	selection = PlanetSelection.new()
	selection.rig = rig
	selection.markers = markers
	selection.region = region
	selection.surface_service = surface_service
	selection.survey = survey
	add_child(selection)
	selection.selected.connect(select_marker)
	selection.back_requested.connect(go_back)
	selection.pointer_changed.connect(hover_at)
	hud.back_requested.connect(go_back)
	hud.panel.explore_requested.connect(explore_mission)
	hud.panel.deploy_requested.connect(deploy)
	hud.panel.terrain_requested.connect(drive_bradbury)
	patch_builder=TerrainPatchBuilder.new()
	patch_builder.service=surface_service
	add_child(patch_builder)
	patch_builder.completed.connect(patch_prepared)
	patch_builder.failed.connect(func(message: String): patch_building=false; terrain.set_process(true); hud.notice.text=message; selection.enabled=true)
	deployment = PlanetDeployment.new()
	deployment.prepare(region)
	deployment.rig = rig
	deployment.cover = hud.cover
	add_child(deployment)
	deployment.surface_approach.connect(func(): set_state(Navigation.SURFACE_APPROACH); hud.notice.text = "APPROACHING  /  " + deployment.destination_title.to_upper())
	deployment.handoff.connect(func(): set_state(Navigation.DEPLOYMENT_TRANSITION); hud.notice.text = "ENTERING  /  " + deployment.destination_label.to_upper())
	deployment.failed.connect(deployment_failed)
	routes = PlanetRouteRenderer.new()
	routes.radius = definition.radius
	routes.surface_service = surface_service
	planet.add_child(routes)
	if mission != null:
		routes.route = mission.resolved_route()
		routes.rebuild()
	var available := layer_manager.available_layers()
	for id in available: hud.layer_selector.add_item(layer_manager.layers[id].title)
	hud.layer_selector.visible = available.size()>1
	hud.layer_selector.item_selected.connect(func(index: int): layer_manager.set_view_mode(available[index]))
	get_viewport().size_changed.connect(func(): dirty = true)
	refresh()

func set_state(next: int) -> void:
	state = next
	navigation_changed.emit(state)
	dirty = true

func remember() -> void:
	history.append({"state":state,"view":rig.snapshot(),"selected":selected_id})

func select_marker(data: PlanetMarkerData, double_click: bool = false) -> void:
	if deployment.active or data == null or not data.is_valid(): return
	if selected_id != data.id or state == Navigation.PLANET_VIEW: remember()
	selected_id = data.id
	markers.selected_id = data.id
	if cell_open: close_cell()
	if data is PlanetMission:
		mission = data
		region = find_marker(mission.region_id) as PlanetRegion
		site = find_marker(mission.site_id) as PlanetMissionSite
		selection.region = region
		routes.route = mission.resolved_route()
		routes.rebuild()
	elif not data.mission_id.is_empty():
		mission = find_marker(data.mission_id) as PlanetMission
		if mission != null:
			region = find_marker(mission.region_id) as PlanetRegion
			site = find_marker(mission.site_id) as PlanetMissionSite
	var target := data
	if data is PlanetMission and region != null: target = region
	set_state(Navigation.MISSION_FOCUS if data.category == "site" else Navigation.REGION_FOCUS)
	var focus_distance := 1.006 if state == Navigation.MISSION_FOCUS else 1.05
	if not double_click: focus_distance=minf(focus_distance,rig.distance/rig.radius)
	rig.focus_on_coordinates(target.latitude,target.longitude,focus_distance)
	show_selection()

func find_marker(id: String) -> PlanetMarkerData:
	for data in definition.markers:
		if data != null and data.id == id: return data
	return null

func show_selection() -> void:
	var data := find_marker(selected_id)
	if data == null:
		hud.panel.hide_panel()
		hud.breadcrumb.text = "ORBITAL"
		return
	hud.panel.show_mission(data,mission,region,state == Navigation.MISSION_FOCUS)
	if data.id.begins_with("scout_"):
		hud.panel.explore.visible=false; hud.panel.deploy.visible=false
	if data is PlanetScienceSite:
		hud.panel.explore.visible=true; hud.panel.explore.text="DRIVE SCIENCE AREA"
		hud.panel.terrain.visible=false
		hud.panel.details.text="CURIOSITY SCIENCE CAMPAIGN · "+data.date
		hud.panel.note.text="Archived rover position; sample-point offset and absolute accuracy unspecified."
		hud.panel.deploy.visible=false
	hud.breadcrumb.text = "← MARS  /  " + (region.title.to_upper() if region != null else data.title.to_upper())
	if selection.controller_active:
		if hud.panel.explore.visible: hud.panel.explore.grab_focus()
		else: hud.panel.deploy.grab_focus()

func explore_mission() -> void:
	var science_target := find_marker(selected_id) as PlanetScienceSite
	if science_target!=null:
		var candidate := TerrainMissionRegion.new()
		candidate.latitude=science_target.latitude; candidate.longitude=science_target.longitude; candidate.title=science_target.title
		candidate.origin_radius_m=float(surface_service.sample(candidate.latitude,candidate.longitude).get("radial_m",0))
		prepare_patch(candidate); return
	if site == null or deployment.active: return
	remember()
	selected_id = site.id
	markers.selected_id = site.id
	set_state(Navigation.MISSION_FOCUS)
	rig.focus_on_coordinates(site.latitude,site.longitude,1.00065,1.8)
	show_selection()

func deploy() -> void:
	close_cell()
	survey.set_enabled(false)
	grid_toggle.button_pressed = false
	streamer.cancel()
	if region == null or site == null or deployment.active: return
	remember()
	hud.notice.text = "PREPARING DESCENT  /  " + region.title.to_upper()
	deployment.start(region,site)
	if deployment.active:
		set_state(Navigation.SURFACE_APPROACH)
		hud.transition_ui(true)
		markers.deployment = true
		selection.enabled = false

func deployment_failed(message: String) -> void:
	markers.deployment = false
	selection.enabled = true
	hud.transition_ui(false)
	if not history.is_empty(): history.pop_back()
	set_state(Navigation.MISSION_FOCUS)
	if site != null:
		selected_id = site.id
		rig.focus_on_coordinates(site.latitude,site.longitude,1.00065,0.8)
	show_selection()
	hud.notice.text = message

func go_back() -> void:
	if patch_building:
		patch_builder.cancel()
		terrain.set_process(true)
		patch_building=false
		selection.enabled=true
		hud.notice.text="Terrain preparation cancelled"
		return
	if cell_open:
		close_cell()
		return
	if deployment.active:
		if deployment.handed_off: return
		deployment.cancel()
		markers.deployment = false
		selection.enabled = true
		hud.transition_ui(false)
	if history.is_empty(): return
	var previous: Dictionary = history.pop_back()
	selected_id = previous.selected
	markers.selected_id = selected_id
	set_state(previous.state)
	rig.restore(previous.view)
	hud.notice.text = ""
	show_selection()

func hover_at(position: Vector2) -> void:
	var data := markers.pick(position)
	var id := data.id if data != null else ""
	if id != markers.hovered_id:
		markers.hovered_id = id
		dirty = true

func _input(event: InputEvent) -> void:
	if grid_toggle!=null and grid_toggle.visible and ((event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_G) or (event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_X)):
		grid_toggle.button_pressed=not grid_toggle.button_pressed
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and (deployment.active or patch_building):
		go_back()
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B and (deployment.active or patch_building):
		go_back()

func _process(dt: float) -> void:
	refresh_clock += dt
	if selection.controller_active: hover_at(markers.size*0.5)
	grid_toggle.visible = not deployment.active and rig.distance/definition.radius<1.22
	if dirty: refresh()
	if refresh_clock >= 0.1:
		refresh_clock = 0
		hud.update_view(Vector2(rad_to_deg(rig.pitch),PlanetCoordinates.normalize_longitude(rad_to_deg(rig.yaw))),(rig.distance-definition.radius)/definition.radius*definition.physical_radius_km,selection.controller_active)
		if hud.debug_label.visible:
			hud.debug_label.text = "STATE %s\nSELECTED %s\nDIST %.4f  FPS %d\nLAYER %s" % [Navigation.keys()[state],selected_id,rig.distance,Engine.get_frames_per_second(),layer_manager.active_id]

func refresh() -> void:
	dirty = false
	markers.refresh(rig.distance/definition.radius)
	var anchor_id := site.id if state == Navigation.MISSION_FOCUS and site != null else selected_id
	hud.place_panel(markers.anchor(anchor_id))

func _exit_tree() -> void:
	get_window().content_scale_aspect = previous_aspect

func stream_status(message: String) -> void:
	hud.notice.text=message
	if cell_open: show_cell(survey.selected_cell,false)

func build_survey_ui() -> void:
	grid_toggle = CheckButton.new()
	grid_toggle.text = "SURVEY GRID"
	grid_toggle.position = Vector2(28,155)
	hud.add_child(grid_toggle)
	grid_toggle.toggled.connect(toggle_grid)
	cell_panel = PanelContainer.new()
	cell_panel.custom_minimum_size = Vector2(360,0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025,0.03,0.035,0.95)
	style.content_margin_left=18
	style.content_margin_right=18
	style.content_margin_top=16
	style.content_margin_bottom=16
	style.border_width_left=2
	style.border_color=Color("b49570")
	cell_panel.add_theme_stylebox_override("panel",style)
	hud.add_child(cell_panel)
	var column := VBoxContainer.new()
	cell_panel.add_child(column)
	cell_text = RichTextLabel.new()
	cell_text.bbcode_enabled=true
	cell_text.fit_content=false
	cell_text.scroll_active=true
	cell_text.custom_minimum_size=Vector2(325,390)
	cell_text.add_theme_font_size_override("normal_font_size",13)
	cell_text.meta_clicked.connect(open_source)
	column.add_child(cell_text)
	var fetch := Button.new()
	fetch.text="FETCH AVAILABLE DETAIL"
	fetch.pressed.connect(func(): streamer.request_cell(survey.selected_cell.bounds,1024))
	column.add_child(fetch)
	var drive := Button.new()
	drive.text="DRIVE LOCAL TERRAIN"
	drive.pressed.connect(func():
		if not survey.selected_cell.is_empty(): prepare_patch(TerrainMissionRegion.from_cell(survey.selected_cell,surface_service)))
	column.add_child(drive)
	var close := Button.new()
	close.text="BACK TO MISSION"
	close.pressed.connect(close_cell)
	column.add_child(close)
	cell_panel.visible=false

func open_source(url: Variant) -> void:
	if str(url).begins_with("https://"): OS.shell_open(str(url))

func toggle_grid(value: bool) -> void:
	survey.set_enabled(value)
	if value:
		hud.panel.explore.release_focus()
		hud.panel.deploy.release_focus()
		grid_toggle.release_focus()
	if not value: close_cell()

func show_cell(cell: Dictionary, fetch: bool = true) -> void:
	if cell.is_empty(): return
	cell_open=true
	hud.panel.hide_panel()
	cell_panel.visible=true
	var bounds: Rect2 = cell.bounds
	var coverage := survey.coverage(cell)
	var text := "[color=#edc395]SURVEY CELL[/color]\nLAT  %.6f → %.6f°\nLON  %.6f → %.6f° E\n\nDISPLAYABLE DATA\nMOLA · 926 m grid spacing\n" % [bounds.position.y,bounds.end.y,bounds.position.x,bounds.end.x]
	for loaded in coverage.loaded: text+=str(loaded)+"\n"
	text+="\nPUBLISHED FOOTPRINTS\n"
	if coverage.published.is_empty(): text+="No regional records in bundled catalog\n"
	var shown := 0
	for published in coverage.published:
		if shown>=3: break
		text+="[url=%s]%s · %.1f m source posts[/url]\n" % [published.url,published.source,published.spacing]
		shown+=1
	text+="Footprint overlap may contain invalid pixels.\n\nMISSIONS  "+(", ".join(coverage.missions) if not coverage.missions.is_empty() else "No landing anchors in this cell")
	var candidate := TerrainMissionRegion.from_cell(cell,surface_service)
	text+="\nPLAYABLE CANDIDATE  %.0f × %.0f m at cell center\nIncludes %.0f m scenery collar; source resolution varies.\n" % [candidate.size_m.x,candidate.size_m.y,candidate.collar_m]
	text+="\nKNOWN ACQUISITIONS  "+str(coverage.date_range)+"\nRegional dates may be unknown.\nACCURACY  See product metadata; spacing is not accuracy\n\nGRID  dashed MOLA · paired CTX · solid HiRISE"
	cell_text.text=text
	cell_text.custom_minimum_size.y=clampf(hud.size.y-310,220,470)
	cell_panel.reset_size()
	cell_panel.position=Vector2(maxf(28,hud.size.x-390),180)
	if fetch and not streamer.offline: streamer.request_cell(bounds)

func close_cell() -> void:
	cell_open=false
	if cell_panel!=null: cell_panel.visible=false
	if survey!=null: survey.selected_cell.clear(); survey.last_key=""
	if streamer!=null: streamer.cancel()
	if hud!=null: show_selection()

func drive_bradbury() -> void:
	if site==null: return
	var candidate := TerrainMissionRegion.new()
	candidate.title="Bradbury Landing terrain"
	candidate.latitude=site.latitude
	candidate.longitude=site.longitude
	candidate.tile_id="Bradbury · mission anchor"
	candidate.origin_radius_m=float(surface_service.sample(candidate.latitude,candidate.longitude).radial_m)
	prepare_patch(candidate)

func prepare_patch(candidate: TerrainMissionRegion) -> void:
	if deployment.active or patch_builder.busy or not candidate.valid(): return
	streamer.cancel()
	patch_graph=TerrainGenerationGraph.standard(candidate.seed)
	var route := mission.resolved_route() if mission!=null else null
	if route!=null and not route.development_only:
		var points: Array = []
		for waypoint in route.points_until():
			var point := candidate.local_from_geographic(waypoint.latitude,waypoint.longitude)
			if candidate.playable_bounds().has_point(point): points.append(point)
		patch_graph.node("route").parameters.points=points
		patch_graph.node("route").parameters.origin="official: "+route.id
	patch_building=true
	terrain.set_process(false)
	selection.enabled=false
	hud.notice.text="PREPARING SOURCED TERRAIN  /  "+candidate.title.to_upper()+" · ESC to cancel"
	if not patch_builder.start(patch_graph,candidate):
		terrain.set_process(true)
		patch_building=false
		selection.enabled=true
		hud.notice.text="Terrain preparation unavailable; please retry."

func patch_prepared(result: TerrainPatchResult) -> void:
	if not patch_building: return
	terrain.set_process(true)
	patch_building=false
	var target := PlanetRegion.new()
	target.title=result.region.title
	target.latitude=result.region.latitude
	target.longitude=result.region.longitude
	target.deployment_scene="res://procedural_terrain/mission.tscn"
	target.deployment_label="Sourced local terrain · procedural rocks"
	var destination := PlanetMissionSite.new()
	destination.title=result.region.title
	destination.latitude=result.region.latitude
	destination.longitude=result.region.longitude
	remember()
	close_cell()
	survey.set_enabled(false)
	grid_toggle.button_pressed=false
	deployment.start_patch(target,destination,{"result":result,"graph":patch_graph,"service":surface_service,"evaluator":patch_builder.evaluator})
	if deployment.active:
		set_state(Navigation.SURFACE_APPROACH)
		hud.transition_ui(true)
		markers.deployment=true
	else: selection.enabled=true
