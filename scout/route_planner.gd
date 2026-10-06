class_name ScoutRoutePlanner
extends RefCounted

const STEP := 2.0

static func plan(request: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var field: TerrainHeightField = request.field
	var bounds: Rect2 = field.region.playable_bounds().grow(-1.0)
	var count := Vector2i(floori(bounds.size.x/STEP)+1,floori(bounds.size.y/STEP)+1)
	var grid := AStarGrid2D.new()
	grid.region=Rect2i(Vector2i.ZERO,count); grid.cell_size=Vector2.ONE*STEP; grid.offset=bounds.position
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var risk := Image.create(count.x,count.y,false,Image.FORMAT_RGBA8)
	var blocked := 0
	for y in count.y:
		for x in count.x:
			var id := Vector2i(x,y)
			var p := bounds.position+Vector2(x,y)*STEP
			var sample := field.sample(p.x,p.y)
			var slope := rad_to_deg(acos(clampf(field.normal(p.x,p.y).y,-1,1))) if sample.valid else 90.0
			var solid: bool = not sample.valid or slope>=15.0
			for rock: Dictionary in request.get("rocks",[]):
				if p.distance_to(Vector2(rock.position.x,rock.position.z))<rock.size*maxf(rock.shape.x,rock.shape.z)+1.0: solid=true; break
			grid.set_point_solid(id,solid)
			grid.set_point_weight_scale(id,1.0+4.0*pow(clampf((slope-8.0)/7.0,0.0,1.0),2))
			risk.set_pixel(x,y,Color(clampf(slope/30.0,0,1),1.0 if sample.valid else 0.0,0,1))
			if solid: blocked+=1
	var start := Vector2i(((request.start-bounds.position)/STEP).round())
	var goal := Vector2i(((request.goal-bounds.position)/STEP).round())
	var points := PackedVector2Array()
	if grid.is_in_boundsv(start) and grid.is_in_boundsv(goal) and not grid.is_point_solid(start) and not grid.is_point_solid(goal):
		points=grid.get_point_path(start,goal)
	# Revalidate at <=1 m, including the requested endpoint connectors.
	if not points.is_empty():
		points.insert(0,request.start); points.append(request.goal)
		for i in range(1,points.size()):
			var n := maxi(1,ceili(points[i-1].distance_to(points[i])))
			for j in range(n+1):
				var p := points[i-1].lerp(points[i],float(j)/n)
				var sample := field.sample(p.x,p.y)
				if not sample.valid or field.normal(p.x,p.y).y<cos(deg_to_rad(15)): points.clear(); break
				for rock: Dictionary in request.get("rocks",[]):
					if p.distance_to(Vector2(rock.position.x,rock.position.z))<rock.size*maxf(rock.shape.x,rock.shape.z)+1.0: points.clear(); break
				if points.is_empty(): break
			if points.is_empty(): break
	return {"generation":request.generation,"points":points,"state":"revised proposal" if points.size()>1 else "no route found","blocked_cells":blocked,"worker_ms":float(Time.get_ticks_usec()-started)/1000,"step_m":STEP,"risk_map":risk,"risk_bounds":bounds}
