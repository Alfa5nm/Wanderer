class_name PlanetMarkerManager
extends Control

var markers: Array[PlanetMissionMarker] = []
var surface_service: PlanetSurfaceService
var camera: Camera3D
var planet: Node3D
var radius := 1.0
var selected_id := ""
var hovered_id := ""
var deployment := false
var distance := 3.4

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func configure(definition: PlanetDefinition, body: Node3D, view: Camera3D) -> void:
	planet = body
	camera = view
	radius = definition.radius
	for data in definition.markers:
		if data == null or not data.is_valid():
			push_warning("Skipping invalid planetary marker")
			continue
		var marker := PlanetMissionMarker.new()
		marker.data = data
		marker.surface_position = PlanetCoordinates.lat_lon_to_local(data.latitude,data.longitude,radius,0.0005*radius)
		add_child(marker)
		marker.update_style()
		markers.append(marker)

static func front_visible(point: Vector3, center: Vector3, camera_position: Vector3) -> bool:
	return (point-center).normalized().dot(camera_position-point) > 0.0000001

func refresh(new_distance: float) -> void:
	distance = new_distance
	for marker in markers:
		var data := marker.data
		if surface_service!=null: marker.surface_position=surface_service.position_at(data.latitude,data.longitude,5)
		var p := planet.to_global(marker.surface_position)
		var in_range := distance >= data.min_distance and distance <= data.max_distance
		if deployment: in_range = data.category == "site"
		# At close scales the landing marker replaces the overlapping mission marker.
		if data.category == "mission" and distance < 1.55: in_range = false
		marker.visible = in_range and front_visible(p, planet.global_position, camera.global_position) and not camera.is_position_behind(p)
		if marker.visible and surface_service!=null: marker.visible=not surface_service.occluded(planet.to_local(camera.global_position),marker.surface_position)
		if marker.visible:
			marker.position = camera.unproject_position(p)
			marker.label.position = Vector2(19,-42) if data.category == "region" else Vector2(19,-13)
			marker.visible = Rect2(Vector2.ZERO, size).grow(30).has_point(marker.position)
		marker.selected = data.id == selected_id
		marker.hovered = data.id == hovered_id
		marker.update_style()

func pick(screen_position: Vector2) -> PlanetMarkerData:
	var nearest: PlanetMarkerData
	var best := INF
	for marker in markers:
		if not marker.visible or not marker.hit_rect().has_point(screen_position): continue
		var d := screen_position.distance_squared_to(marker.position)
		if d < best:
			best = d
			nearest = marker.data
	return nearest

func anchor(id: String) -> Vector2:
	for marker in markers:
		if marker.data.id == id and marker.visible: return marker.position
	return Vector2(-1000,-1000)
