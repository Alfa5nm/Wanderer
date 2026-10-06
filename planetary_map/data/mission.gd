class_name PlanetMission
extends PlanetMarkerData

@export var agency: String = "NASA / JPL-Caltech"
@export var mission_name: String
@export var mission_type: String = "Rover"
@export var launch_date: String
@export var landing_date: String
@export var end_date: String
@export var status: String = "Landed"
@export var region_id: String
@export var site_id: String
@export var route: PlanetRoute

@export_file("*.tres") var route_file: String

func resolved_route() -> PlanetRoute:
	if route != null: return route
	if route_file.is_empty(): return null
	if not ResourceLoader.exists(route_file):
		push_warning("Optional route unavailable: " + route_file)
		return null
	return load(route_file) as PlanetRoute
