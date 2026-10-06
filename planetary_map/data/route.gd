class_name PlanetRoute
extends Resource

@export var id: String
@export var waypoints: Array[PlanetWaypoint] = []
@export var external_references: PackedStringArray
@export var development_only: bool = false

func points_until(sol: int = -1, date: String = "") -> Array[PlanetWaypoint]:
	var points: Array[PlanetWaypoint] = []
	for point in waypoints:
		if point == null or not PlanetCoordinates.valid(point.latitude, point.longitude): continue
		if sol >= 0 and (point.sol < 0 or point.sol > sol): continue
		if not date.is_empty() and (point.date.is_empty() or point.date > date): continue
		points.append(point)
	return points
