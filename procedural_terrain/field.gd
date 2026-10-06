class_name TerrainHeightField
extends RefCounted

var service: PlanetSurfaceService
var region: TerrainMissionRegion
var cache: Dictionary = {}
var sources: Dictionary = {}

func sample(x: float,z: float) -> Dictionary:
	var key = Vector2(x,z)
	if cache.has(key): return cache[key]
	var ll = region.geographic64(x,z)
	var data = service.sample(ll[0],ll[1])
	var radial = float(data.get("radial_m",NAN))
	var valid = bool(data.get("valid",false)) and is_finite(radial)
	var nominal = sqrt(region.origin_radius_m*region.origin_radius_m+x*x+z*z)
	var height = radial*region.origin_radius_m/nominal-region.origin_radius_m if valid else NAN
	var value = {"height":height,"valid":valid,"geo":Vector2(ll[0],ll[1]),"source":data.get("source","unknown"),"spacing_m":data.get("spacing_m",0)}
	if valid: sources[value.source]=value.spacing_m
	cache[key]=value
	return value

func normal(x: float,z: float,step: float = 0.0) -> Vector3:
	if step<=0: step=maxf(1.0,float(sample(x,z).spacing_m))
	var dx = float(sample(x+step,z).height)-float(sample(x-step,z).height)
	var dz = float(sample(x,z+step).height)-float(sample(x,z-step).height)
	if not is_finite(dx) or not is_finite(dz): return Vector3.UP
	return Vector3(-dx/(2*step),1,-dz/(2*step)).normalized()

func curvature(x: float,z: float,step: float = 0.0) -> float:
	if step<=0: step=maxf(1.0,float(sample(x,z).spacing_m))
	var value = (float(sample(x+step,z).height)+float(sample(x-step,z).height)+float(sample(x,z+step).height)+float(sample(x,z-step).height)-4*float(sample(x,z).height))/(step*step)
	return value if is_finite(value) else 0.0
