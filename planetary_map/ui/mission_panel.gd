class_name PlanetMissionPanel
extends PanelContainer

signal explore_requested
signal terrain_requested
signal deploy_requested
var title: Label
var details: Label
var description: Label
var explore: Button
var terrain: Button
var deploy: Button
var note: Label
var selected_data: PlanetMarkerData

func _ready() -> void:
	custom_minimum_size = Vector2(310,0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025,0.03,0.035,0.91)
	style.border_color = Color(0.72,0.52,0.33,0.6)
	style.border_width_left = 2
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	add_theme_stylebox_override("panel",style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	add_child(column)
	title = make_label(column, 22, Color("f0d9c0"))
	details = make_label(column, 13, Color("cfa77d"))
	description = make_label(column, 14, Color("b8b9b9"))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 270
	explore = make_button(column,"EXPLORE MISSION")
	terrain = make_button(column,"DRIVE LOCAL TERRAIN")
	terrain.pressed.connect(func(): terrain_requested.emit())
	deploy = make_button(column,"DEPLOY  →")
	note = make_label(column,12,Color("969896"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 270
	explore.pressed.connect(func(): explore_requested.emit())
	deploy.pressed.connect(func(): deploy_requested.emit())
	visible = false

func make_label(parent: Node, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func make_button(parent: Node, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.add_theme_font_size_override("font_size",13)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11,0.105,0.09,0.9)
	style.border_width_bottom = 1
	style.border_color = Color("8e7257")
	button.add_theme_stylebox_override("normal", style)
	var highlight := style.duplicate()
	highlight.bg_color = Color("332a20")
	button.add_theme_stylebox_override("hover", highlight)
	button.add_theme_stylebox_override("focus", highlight)
	parent.add_child(button)
	return button

func show_mission(data: PlanetMarkerData, mission: PlanetMission, region: PlanetRegion, inspecting: bool) -> void:
	selected_data = data
	if mission == null:
		title.text = data.title.to_upper()
		details.text = data.subtitle
		description.text = data.description
		explore.visible = false
		terrain.visible = false
		deploy.visible = false
		note.text = ""
	else:
		title.text = data.title.to_upper()
		details.text = "%s\n%s\n\nLANDED  %s UTC" % [mission.mission_name.to_upper(),mission.title.to_upper(),mission.landing_date]
		description.text = mission.description if inspecting else data.description
		explore.visible = not inspecting and not mission.site_id.is_empty()
		terrain.visible = mission.id=="curiosity"
		deploy.visible = region != null and not region.deployment_scene.is_empty()
		note.text = "Destination: " + region.deployment_label if region != null else ""
	reset_size.call_deferred()
	visible = true
	modulate.a = 0
	create_tween().tween_property(self,"modulate:a",1.0,0.25)

func hide_panel() -> void:
	explore.release_focus()
	deploy.release_focus()
	visible = false
