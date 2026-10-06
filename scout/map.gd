class_name ScoutMap
extends Control

var world: Node
var session: ScoutSession
var image: Texture2D
var map_rect := Rect2(8,26,224,224)

func _ready() -> void:
	custom_minimum_size=Vector2(240,288)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	session=ScoutSession.obtain(get_tree())
	image=ImageTexture.create_from_image(world.result.image)
	session.map_changed.connect(queue_redraw)

func project(point: Vector2) -> Vector2:
	var bounds: Rect2 = world.result.region.terrain_bounds()
	return map_rect.position+(point-bounds.position)/bounds.size*map_rect.size

func _process(_delta: float) -> void: queue_redraw()

func _draw() -> void:
	if image==null: return
	draw_style_box(panel(),Rect2(Vector2.ZERO,Vector2(240,288)))
	draw_string(ThemeDB.fallback_font,Vector2(8,18),"SCOUT ASSESSMENT · PROPOSED ROUTE",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("edc395"))
	draw_texture_rect(image,map_rect,false,Color(0.65,0.65,0.65))
	for finding: Dictionary in session.findings.values():
		var point: Vector2 = world.result.region.local_from_geographic(finding.latitude,finding.longitude)
		if not world.result.region.terrain_bounds().has_point(point): continue
		var color := Color("b7d0b2") if finding.kind=="clear_slope" else Color("efbb70") if finding.kind=="slope_caution" else Color("ed755f")
		draw_circle(project(point),1.5 if finding.kind=="clear_slope" else 4.0,color)
	var route: Dictionary = session.route
	if route.get("origin","")==world.result.region.signature():
		var points: PackedVector2Array = route.get("points",PackedVector2Array())
		var inspected: Array = route.get("inspected",[])
		for i in range(1,points.size()):
			var verified: bool = inspected.size()>i and inspected[i] and inspected[i-1]
			draw_line(project(points[i-1]),project(points[i]),Color("86bdb5") if verified else Color("dfb077"),2)
		if not points.is_empty(): draw_circle(project(points[-1]),5,Color("edc395"),false,2)
	draw_circle(project(Vector2(world.rover.chassis.position.x,world.rover.chassis.position.z)),4,Color.WHITE)
	if world.astronaut!=null:
		var p := project(Vector2(world.astronaut.position.x,world.astronaut.position.z))
		draw_colored_polygon(PackedVector2Array([p+Vector2(0,-5),p+Vector2(-4,4),p+Vector2(4,4)]),Color("8bcfd4"))
	draw_string(ThemeDB.fallback_font,Vector2(8,265),"RED hazard · AMBER provisional · CYAN assessed",HORIZONTAL_ALIGNMENT_LEFT,-1,10)
	draw_string(ThemeDB.fallback_font,Vector2(8,280),route.get("state","No route proposed").to_upper(),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("edc395"))

func panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color=Color(0.02,0.025,0.03,0.88); return style
