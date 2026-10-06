class_name PlanetCoordinates
extends RefCounted

# Planetocentric degrees, east positive. +Y north; lon 0 = +Z; lon 90 = +X.
static func valid(lat: float, lon: float) -> bool:
	return is_finite(lat) and is_finite(lon) and absf(lat) <= 90.0

static func normalize_longitude(lon: float) -> float:
	return fposmod(lon + 180.0, 360.0) - 180.0

static func lat_lon_to_local(lat: float, lon: float, radius: float = 1.0, altitude: float = 0.0) -> Vector3:
	if not valid(lat, lon) or not is_finite(radius) or not is_finite(altitude) or radius <= 0 or radius + altitude <= 0:
		push_warning("Invalid planetary coordinates or radius")
		return Vector3.ZERO
	var phi := deg_to_rad(lat)
	var theta := deg_to_rad(normalize_longitude(lon))
	return Vector3(cos(phi)*sin(theta), sin(phi), cos(phi)*cos(theta))*(radius+altitude)

static func local_to_lat_lon(position: Vector3) -> Vector2:
	if not position.is_finite() or position.length_squared() < 0.00000001:
		return Vector2(INF, INF)
	var p := position.normalized()
	return Vector2(rad_to_deg(asin(clampf(p.y, -1, 1))), normalize_longitude(rad_to_deg(atan2(p.x, p.z))))

static func lat_lon_to_world(lat: float, lon: float, radius: float, altitude: float, planet_transform: Transform3D) -> Vector3:
	return planet_transform * lat_lon_to_local(lat, lon, radius, altitude)

static func world_to_lat_lon(position: Vector3, planet_transform: Transform3D) -> Vector2:
	return local_to_lat_lon(planet_transform.affine_inverse() * position)

# Equirectangular NASA Viking map: -180 at left, 0 at center, +180 at right.
static func lat_lon_to_uv(lat: float, lon: float) -> Vector2:
	return Vector2((normalize_longitude(lon)+180.0)/360.0, (90.0-lat)/180.0)

static func surface_hit(origin: Vector3, direction: Vector3, radius: float) -> Vector3:
	var b := origin.dot(direction)
	var c := origin.length_squared()-radius*radius
	var discriminant := b*b-c
	if discriminant < 0: return Vector3.ZERO
	var t := -b-sqrt(discriminant)
	if t < 0: return Vector3.ZERO
	return origin+direction*t
