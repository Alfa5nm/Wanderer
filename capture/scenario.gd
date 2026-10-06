class_name ScoutScenario
extends RefCounted

static func find_local(request: Dictionary) -> Dictionary:
	var field: TerrainHeightField = request.field
	var base := {"field":field,"start":Vector2(-5,0),"goal":Vector2(5,0),"rocks":request.rocks,"generation":0}
	var analysis := ScoutRoutePlanner.plan(base)
	var bounds: Rect2 = analysis.risk_bounds
	var candidates: Array = []
	for y in range(4,analysis.risk_map.get_height()-4,2):
		for x in range(4,analysis.risk_map.get_width()-4,2):
			if analysis.risk_map.get_pixel(x,y).r<0.50: continue
			var p := bounds.position+Vector2(x,y)*2
			if field.sample(p.x,p.y).spacing_m>8: continue
			candidates.append(p)
	candidates.sort_custom(func(a,b): return a.length_squared()<b.length_squared())
	for p: Vector2 in candidates.slice(0,4):
		var normal := field.normal(p.x,p.y)
		var direction := Vector2(normal.x,normal.z).normalized()
		var from := p-direction*12; var to := p+direction*8
		if not bounds.has_point(from) or not bounds.has_point(to): continue
		if field.normal(from.x,from.y).y<cos(deg_to_rad(8)): continue
		base.start=from; base.goal=to
		var route := ScoutRoutePlanner.plan(base)
		if route.points.size()>1:
			return {"ready":true,"kind":"DEM-DERIVED SLOPE","start":from,"goal":to,"hazard":p,"risk_map":analysis.risk_map,"risk_bounds":bounds}
	var rocks: Array = request.rocks.duplicate()
	rocks.sort_custom(func(a,b): return a.position.length_squared()<b.position.length_squared())
	for rock: Dictionary in rocks:
		var p := Vector2(rock.position.x,rock.position.z)
		var from := p-Vector2(0,12); var to := p+Vector2(0,6)
		base.start=from; base.goal=to
		var route := ScoutRoutePlanner.plan(base)
		if route.points.size()>1 and field.normal(from.x,from.y).y>=cos(deg_to_rad(8)):
			return {"ready":true,"kind":"SIMULATED OBSTACLE","start":from,"goal":to,"hazard":p,"risk_map":analysis.risk_map,"risk_bounds":bounds}
	return {"ready":false,"message":"No safe repeatable scenario in this patch","risk_map":analysis.risk_map,"risk_bounds":bounds}

static func find(request: Dictionary) -> Dictionary:
	var local := find_local(request)
	if local.get("kind","")=="DEM-DERIVED SLOPE": return local
	var service: PlanetSurfaceService = request.field.service
	var attempts := 0
	var started := Time.get_ticks_msec()
	for dataset: PlanetDataset in service.datasets:
		if dataset.kind!="elevation" or not dataset.loaded or dataset.prepared_spacing_m>8: continue
		if not dataset.bounds.intersects(Rect2(137,-5,1,1)): continue
		for y in range(1,16):
			for x in range(1,16):
				if attempts>=4 or Time.get_ticks_msec()-started>20000: return local
				var ll := dataset.bounds.position+dataset.bounds.size*Vector2(float(x)/16,float(y)/16)
				var region := TerrainMissionRegion.new(); region.latitude=ll.y; region.longitude=ll.x
				region.origin_radius_m=float(service.sample(ll.y,ll.x).get("radial_m",0))
				if not region.valid(): continue
				var field := TerrainHeightField.new(); field.region=region; field.service=service
				var value := field.sample(0,0)
				if not value.valid or value.spacing_m>8 or field.normal(0,0).y>cos(deg_to_rad(15)): continue
				attempts+=1
				var candidate := find_local({"field":field,"rocks":[]})
				if candidate.get("kind","")=="DEM-DERIVED SLOPE":
					region.title="Gale sourced slope scout demonstration"
					candidate["region"]=region; candidate["search_attempts"]=attempts
					return candidate
	local["search_attempts"]=attempts
	return local
