class_name PlanetHUD
extends Control

signal back_requested
var identity: VBoxContainer
var heading: Label
var breadcrumb: Button
var telemetry: Label
var controls: Label
var notice: Label
var debug_label: Label
var reticle: Control
var panel: PlanetMissionPanel
var wait_for_terrain := false
var boot_cover: ColorRect
var boot_fading := false
var cover: ColorRect
var layer_selector: OptionButton
var fading := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	boot_cover = ColorRect.new()
	boot_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	boot_cover.color = Color.BLACK
	boot_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(boot_cover)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margins.add_theme_constant_override("margin_"+side,28)
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margins)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margins.add_child(column)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	var identity_panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color=Color(0.025,0.03,0.035,0.72)
	style.content_margin_left=10
	style.content_margin_right=10
	style.content_margin_top=8
	style.content_margin_bottom=8
	identity_panel.add_theme_stylebox_override("panel",style)
	identity_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	top.add_child(identity_panel)
	identity = VBoxContainer.new()
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity_panel.add_child(identity)
	heading = label(identity,"MARS",38,Color("e8d6c3"))
	label(identity,"PLANETARY EXPLORATION INTERFACE",12,Color("b29475"))
	breadcrumb = Button.new()
	breadcrumb.text = "ORBITAL"
	breadcrumb.flat = true
	breadcrumb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	breadcrumb.add_theme_font_size_override("font_size",13)
	breadcrumb.pressed.connect(func(): back_requested.emit())
	identity.add_child(breadcrumb)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	telemetry = label(top,"",13,Color("afaa9e"))
	telemetry.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(space)
	notice = label(column,"",14,Color("edc395"))
	controls = label(column,"DRAG  Orbit    SCROLL  Zoom    CLICK  Select    DOUBLE-CLICK  Focus",13,Color("a9a59c"))
	label(column,"THE CURIOSITY VOYAGE   /   NASA SPACE APPS 2026",11,Color("776e63"))
	panel = PlanetMissionPanel.new()
	add_child(panel)
	layer_selector = OptionButton.new()
	layer_selector.position = Vector2(28,155)
	layer_selector.visible = false
	add_child(layer_selector)
	debug_label = label(self,"",12,Color("e5a67a"))
	debug_label.position = Vector2(28,192)
	debug_label.visible = OS.is_debug_build() and "--planet-debug" in OS.get_cmdline_user_args()
	reticle = Control.new()
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.draw.connect(func():
		reticle.draw_line(Vector2(-8,0),Vector2(-3,0),Color("d8c1a3"),1)
		reticle.draw_line(Vector2(3,0),Vector2(8,0),Color("d8c1a3"),1)
		reticle.draw_line(Vector2(0,-8),Vector2(0,-3),Color("d8c1a3"),1)
		reticle.draw_line(Vector2(0,3),Vector2(0,8),Color("d8c1a3"),1))
	reticle.visible = false
	add_child(reticle)
	cover = ColorRect.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.color = Color(0,0,0,0)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cover)
	if not wait_for_terrain: begin_boot_fade()

func begin_boot_fade() -> void:
	if boot_fading: return
	boot_fading=true
	create_tween().tween_property(boot_cover,"color:a",0.0,1.3)

func label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_constant_override("outline_size",4)
	result.add_theme_color_override("font_outline_color",Color(0.03,0.025,0.025,1.0))
	result.add_theme_color_override("font_color",color)
	parent.add_child(result)
	return result

func update_view(coordinates: Vector2, altitude_km: float, controller: bool) -> void:
	telemetry.text = "LAT  %+.2f°\nLON  %+.2f° E\nDIST  %s km" % [coordinates.x, coordinates.y, String.num(altitude_km,0)]
	reticle.position = size*0.5
	reticle.visible = controller and not fading
	controls.text = "LEFT STICK  Orbit    TRIGGERS  Zoom    A  Select    B  Back    X  Grid" if controller else "DRAG  Orbit    SCROLL  Zoom    CLICK  Select    DOUBLE-CLICK  Focus    ESC  Back    G  Grid"

func place_panel(anchor: Vector2) -> void:
	if not panel.visible: return
	if anchor.x < -100:
		panel.position = Vector2(size.x-panel.size.x-28,180)
	else:
		var x := anchor.x+185
		if x+panel.size.x > size.x-28: x = anchor.x-panel.size.x-48
		panel.position = Vector2(clampf(x,28,size.x-panel.size.x-28),clampf(anchor.y-90,155,maxf(155,size.y-panel.size.y-90)))

func transition_ui(active: bool) -> void:
	fading = active
	panel.hide_panel()
	identity.visible = not active
	heading.visible = not active
	telemetry.visible = not active
	controls.visible = not active
	breadcrumb.visible = not active
	reticle.visible = false
