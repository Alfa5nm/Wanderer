class_name PlanetMissionMarker
extends Control

var data: PlanetMarkerData
var surface_position := Vector3.ZERO
var hovered := false
var selected := false
var label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(19, -13)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_constant_override("outline_size",2)
	label.add_theme_color_override("font_outline_color",Color("28221f"))
	label.add_theme_color_override("font_color", Color("eac19b"))
	add_child(label)

func update_style() -> void:
	label.text = data.title.to_upper()
	label.visible = true
	queue_redraw()

func _draw() -> void:
	var color := Color("edbb82") if selected or hovered else Color("cfac88")
	var radius := 7.0 if selected or hovered else 6.0
	draw_circle(Vector2.ZERO, 2, color)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 24, color, 1, true)
	if selected:
		draw_line(Vector2(12, 0), Vector2(30, 0), color*Color(1,1,1,0.5), 1, true)

func hit_rect() -> Rect2:
	var rect := Rect2(position-Vector2(22,22), Vector2(44,44))
	if label.visible:
		rect = rect.merge(Rect2(position+label.position, label.size).grow(8))
	return rect
