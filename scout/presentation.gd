class_name ScoutPresentation
extends Node3D

var world: Node
var route_visual: MeshInstance3D
var markers: Node3D
var map: ScoutMap
var notice: Label
var refresh_pending := false
var session: ScoutSession

func _ready() -> void:
	session=ScoutSession.obtain(get_tree())
	markers=Node3D.new(); add_child(markers)
	var layer := CanvasLayer.new(); add_child(layer)
	map=ScoutMap.new(); map.world=world; map.position=Vector2(24,130); layer.add_child(map)
	notice=Label.new(); notice.position=Vector2(28,425); notice.add_theme_font_size_override("font_size",12)
	layer.add_child(notice)
	session.map_changed.connect(schedule_refresh)
	refresh()

func schedule_refresh() -> void:
	if refresh_pending: return
	refresh_pending=true
	refresh.call_deferred()

func refresh() -> void:
	refresh_pending=false
	for child in markers.get_children(): child.queue_free()
	for record: Dictionary in session.findings.values():
		if record.kind=="clear_slope": continue
		var point: Vector2 = world.result.region.local_from_geographic(record.latitude,record.longitude)
		if not world.result.region.playable_bounds().has_point(point): continue
		var label := Label3D.new()
		label.position=Vector3(point.x,world.result.field.sample(point.x,point.y).height+0.7,point.y)
		label.text="SIMULATED OBSTACLE" if record.kind=="simulated_obstacle" else "DERIVED SLOPE %.0f°" % record.slope
		label.font_size=20; label.pixel_size=0.008; label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		markers.add_child(label)
	if route_visual!=null: route_visual.queue_free(); route_visual=null
	var route: Dictionary = session.route
	if route.get("origin","")!=world.result.region.signature(): return
	var points: PackedVector2Array = route.get("points",PackedVector2Array())
	var mesh := ImmediateMesh.new()
	if points.size()>1:
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in range(1,points.size()):
			var a: Vector2 = points[i-1]; var b: Vector2 = points[i]
			var surveyed: Array = route.get("inspected",[])
			mesh.surface_set_color(Color("86bdb5") if surveyed.size()>i and surveyed[i] and surveyed[i-1] else Color("dfb077"))
			mesh.surface_add_vertex(Vector3(a.x,world.result.field.sample(a.x,a.y).height+0.08,a.y))
			mesh.surface_add_vertex(Vector3(b.x,world.result.field.sample(b.x,b.y).height+0.08,b.y))
		mesh.surface_end()
		route_visual=MeshInstance3D.new(); route_visual.mesh=mesh
		var material := StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.vertex_color_use_as_albedo=true
		route_visual.material_override=material; route_visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(route_visual)
	notice.text="15° human planning cutoff · model assumption\n"+route.get("state","")+" · not a historic traverse"
