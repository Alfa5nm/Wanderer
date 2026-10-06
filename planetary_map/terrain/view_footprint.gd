class_name MarsViewFootprint
extends RefCounted

# Request a padded geographic rectangle around visible ray hits, rather than
# only the cell under the center. Split the longitude seam into two real crops.
static func bounds(camera: Camera3D, service: PlanetSurfaceService, center_lon: float) -> Array[Rect2]:
	var viewport := camera.get_viewport().get_visible_rect().size
	var low := Vector2(INF,INF)
	var high := Vector2(-INF,-INF)
	for y in [0.0,0.25,0.5,0.75,1.0]:
		for x in [0.0,0.25,0.5,0.75,1.0]:
			var hit := service.hit(service.render_origin,camera.project_ray_normal(Vector2(x,y)*viewport))
			if hit==Vector3.ZERO: continue
			var geo := PlanetCoordinates.local_to_lat_lon(hit)
			var point := Vector2(center_lon+wrapf(geo.y-center_lon,-180,180),geo.x)
			low=low.min(point)
			high=high.max(point)
	if not low.is_finite(): return []
	var margin := (high-low)*0.30
	low-=margin
	high+=margin
	low.y=maxf(low.y,-90)
	high.y=minf(high.y,90)
	if high.x-low.x>=360: return [Rect2(-180,low.y,360,high.y-low.y)]
	var width := high.x-low.x
	low.x=PlanetCoordinates.normalize_longitude(low.x)
	high.x=low.x+width
	if high.x>180:
		return [Rect2(low.x,low.y,180-low.x,high.y-low.y),Rect2(-180,low.y,high.x-180,high.y-low.y)]
	return [Rect2(low,high-low)]

static func key(rectangles: Array[Rect2]) -> String:
	var result := ""
	for rect in rectangles:
		result+="%.2f/%.2f/%.2f/%.2f;" % [rect.position.x,rect.position.y,rect.size.x,rect.size.y]
	return result
