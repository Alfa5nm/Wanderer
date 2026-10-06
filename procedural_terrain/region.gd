class_name TerrainMissionRegion
extends Resource

@export var title := "Mars terrain patch"
@export var tile_id := ""
@export var tile_bounds := Rect2()
@export var latitude := -4.5895
@export var longitude := 137.4417
@export var size_m := Vector2(256,256)
@export var collar_m := 64.0
@export var origin_radius_m := 3396000.0
@export var seed := 7462

func valid() -> bool:
	return PlanetCoordinates.valid(latitude,longitude) and size_m.is_finite() and size_m.x>=16 and size_m.y>=16 and size_m.x<=2048 and size_m.y<=2048 and is_finite(collar_m) and collar_m>=0 and collar_m<=256

func axes() -> Array[Vector3]:
	var p = deg_to_rad(latitude)
	var t = deg_to_rad(longitude)
	return [Vector3(cos(t),0,-sin(t)),Vector3(cos(p)*sin(t),sin(p),cos(p)*cos(t)),Vector3(-sin(p)*sin(t),cos(p),-sin(p)*cos(t))]

func geographic64(x: float,z: float) -> Array[float]:
	var p := deg_to_rad(latitude)
	var t := deg_to_rad(longitude)
	var px: float = cos(p)*sin(t)*origin_radius_m+cos(t)*x+sin(p)*sin(t)*z
	var py: float = sin(p)*origin_radius_m-cos(p)*z
	var pz: float = cos(p)*cos(t)*origin_radius_m-sin(t)*x+sin(p)*cos(t)*z
	return [rad_to_deg(atan2(py,sqrt(px*px+pz*pz))),PlanetCoordinates.normalize_longitude(rad_to_deg(atan2(px,pz)))]

func geographic(x: float,z: float) -> Vector2:
	var value := geographic64(x,z)
	return Vector2(value[0],value[1])

func local_from_geographic(lat: float,lon: float) -> Vector2:
	var p = deg_to_rad(lat)
	var t = deg_to_rad(lon)
	var a = axes()
	var direction = Vector3(cos(p)*sin(t),sin(p),cos(p)*cos(t))
	var divisor = direction.dot(a[1])
	if divisor<=0: return Vector2.INF
	return Vector2(direction.dot(a[0]),-direction.dot(a[2]))*(origin_radius_m/divisor)

func playable_bounds() -> Rect2:
	return Rect2(-size_m*0.5,size_m)

func terrain_bounds() -> Rect2:
	return playable_bounds().grow(collar_m)

func signature() -> String:
	return JSON.stringify([latitude,longitude,size_m.x,size_m.y,collar_m,origin_radius_m])

static func from_cell(cell: Dictionary,service: PlanetSurfaceService) -> TerrainMissionRegion:
	var result = TerrainMissionRegion.new()
	result.tile_id=str(cell.get("id",""))
	result.tile_bounds=cell.get("bounds",Rect2())
	var center = result.tile_bounds.get_center()
	result.latitude=clampf(center.y,-90,90)
	result.longitude=PlanetCoordinates.normalize_longitude(center.x)
	result.title="Survey terrain · %.4f°, %.4f° E" % [result.latitude,result.longitude]
	var dimensions = result.tile_bounds.size*deg_to_rad(1.0)*service.physical_radius_m
	dimensions.x*=absf(cos(deg_to_rad(result.latitude)))
	# Mission bounds are independent of the streaming address; the collar may cross it.
	result.size_m=Vector2(clampf(dimensions.x,16,256),clampf(dimensions.y,16,256))
	result.origin_radius_m=float(service.sample(result.latitude,result.longitude).get("radial_m",3396000))
	result.seed=absi(result.tile_id.hash())
	return result
