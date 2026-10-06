class_name PlanetRouteRenderer
extends MeshInstance3D

var surface_service: PlanetSurfaceService
var route: PlanetRoute
var radius := 1.0
var current_sol := -1
var current_date := ""

func set_timeline(sol: int = -1, date: String = "") -> void:
	current_sol = sol
	current_date = date
	rebuild()

func rebuild() -> void:
	mesh = null
	if route == null or route.development_only: return
	var points := route.points_until(current_sol, current_date)
	if points.size()<2: return
	var geometry := ImmediateMesh.new()
	geometry.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(1, points.size()):
		var a := PlanetCoordinates.lat_lon_to_local(points[i-1].latitude, points[i-1].longitude)
		var b := PlanetCoordinates.lat_lon_to_local(points[i].latitude, points[i].longitude)
		var count := maxi(1, int(ceil(a.angle_to(b)/deg_to_rad(0.25))))
		for j in count:
			geometry.surface_add_vertex(project(a.slerp(b,float(j)/count)))
			geometry.surface_add_vertex(project(a.slerp(b,float(j+1)/count)))
	geometry.surface_end()
	mesh = geometry
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("c7ae89")
	material_override = material

func project(point: Vector3) -> Vector3:
	if surface_service==null: return point.normalized()*(radius+0.0007)
	var ll := PlanetCoordinates.local_to_lat_lon(point)
	return surface_service.position_at(ll.x,ll.y,5)
