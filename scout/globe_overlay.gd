class_name ScoutGlobeOverlay
extends Node

var globe: Node
var session: ScoutSession
var route_visual: MeshInstance3D
var label: Label

func _ready() -> void:
	session=ScoutSession.obtain(get_tree())
	label=Label.new(); label.position=Vector2(32,208); label.add_theme_font_size_override("font_size",12)
	globe.hud.add_child(label)
	session.map_changed.connect(refresh)
	refresh()

func refresh() -> void:
	for i in range(globe.markers.markers.size()-1,-1,-1):
		var marker: PlanetMissionMarker = globe.markers.markers[i]
		if marker.data.id.begins_with("scout_"):
			globe.markers.markers.remove_at(i); marker.queue_free()
	for i in range(globe.definition.markers.size()-1,-1,-1):
		if globe.definition.markers[i].id.begins_with("scout_"): globe.definition.markers.remove_at(i)
	var count := 0
	for key in session.findings:
		var record: Dictionary = session.findings[key]
		if record.kind=="clear_slope": continue
		if count>=64: break
		var data := PlanetMarkerData.new()
		data.id="scout_"+str(key); data.latitude=record.latitude; data.longitude=record.longitude
		data.category="science"; data.mission_id="curiosity"; data.max_distance=1.03
		data.title="Simulated obstacle" if record.kind=="simulated_obstacle" else "Derived slope %.0f°" % record.slope
		data.description=record.description+"\n"+record.source+"\nNot a new NASA observation; simulated scout assessment."
		globe.definition.markers.append(data)
		var marker := PlanetMissionMarker.new(); marker.data=data
		marker.surface_position=globe.surface_service.position_at(data.latitude,data.longitude,5)
		globe.markers.add_child(marker); marker.update_style(); globe.markers.markers.append(marker)
		count+=1
	if route_visual!=null: route_visual.queue_free(); route_visual=null
	var coordinates: Array = session.route.get("geographic_points",[])
	if coordinates.size()>1:
		var mesh := ImmediateMesh.new(); mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in range(1,coordinates.size()):
			mesh.surface_add_vertex(globe.surface_service.position_at(coordinates[i-1].x,coordinates[i-1].y,10))
			mesh.surface_add_vertex(globe.surface_service.position_at(coordinates[i].x,coordinates[i].y,10))
		mesh.surface_end()
		route_visual=MeshInstance3D.new(); route_visual.mesh=mesh
		var material := StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color=Color("dfb077")
		route_visual.material_override=material; globe.planet.add_child(route_visual)
	label.text="SIMULATED SCOUT ASSESSMENTS · %d findings\n%s · not a historical traverse" % [count,session.route.get("state","")] if count>0 else ""
	globe.dirty=true
