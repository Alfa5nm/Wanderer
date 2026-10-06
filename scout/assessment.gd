class_name ScoutAssessment
extends Node

signal route_ready(route: Dictionary)
var world: Node
var session: ScoutSession
var enabled := true
var elapsed := 0.0
var start := Vector2.ZERO
var goal := Vector2.ZERO
var has_goal := false
var generation := 0
var worker: Thread
var pending := false
var field: TerrainHeightField
var last_plan_ms := 0.0

func _ready() -> void:
	session=ScoutSession.obtain(get_tree())
	field=TerrainHeightField.new(); field.service=world.service; field.region=world.result.region

func propose(from: Vector2,to: Vector2) -> void:
	start=from; goal=to; has_goal=true; generation+=1
	var geo := field.region.geographic64(to.x,to.y)
	session.set_route({"state":"unverified proposal","points":PackedVector2Array([from,to]),"latitude":geo[0],"longitude":geo[1],"origin":field.region.signature()})
	route_ready.emit(session.route)

func replan() -> void:
	if not has_goal: return
	generation+=1; pending=true

func _process(dt: float) -> void:
	if worker!=null and not worker.is_alive():
		var output: Dictionary = worker.wait_to_finish(); worker=null
		if output.generation==generation:
			last_plan_ms=output.worker_ms
			output["origin"]=field.region.signature()
			var geographic: Array = []
			var inspected: Array[bool] = []
			for p in output.points:
				var geo := field.region.geographic64(p.x,p.y)
				geographic.append(Vector2(geo[0],geo[1])); inspected.append(session.inspected(geo[0],geo[1]))
			output["geographic_points"]=geographic; output["inspected"]=inspected
			session.set_route(output); route_ready.emit(output)
	if pending and worker==null:
		pending=false
		var route_field := TerrainHeightField.new(); route_field.region=field.region; route_field.service=field.service
		worker=Thread.new()
		if worker.start(ScoutRoutePlanner.plan.bind({"field":route_field,"start":start,"goal":goal,"rocks":world.result.rocks.duplicate(true),"generation":generation}))!=OK: worker=null
	elapsed+=dt/maxf(Engine.time_scale,0.001)
	if not enabled or world.human_control or elapsed<0.5: return
	elapsed=0.0
	scan()

func scan() -> void:
	var p: Vector3 = world.rover.chassis.global_position
	var forward := Vector2(world.rover.chassis.global_basis.z.x,world.rover.chassis.global_basis.z.z).normalized()
	var side := Vector2(-forward.y,forward.x)
	var discovered := false
	for distance in [2.0,4.0,6.0,8.0,10.0]:
		for offset in [-4.0,-2.0,0.0,2.0,4.0]:
			if absf(offset)>distance: continue
			var point: Vector2 = (Vector2(p.x,p.z)+forward*distance+side*offset).snapped(Vector2.ONE*2)
			if point.distance_to(Vector2(p.x,p.z))>10 or not field.region.playable_bounds().has_point(point): continue
			var sample := field.sample(point.x,point.y)
			if not sample.valid: continue
			var query := PhysicsRayQueryParameters3D.create(p+Vector3.UP*0.5,Vector3(point.x,sample.height+0.1,point.y),1)
			var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and hit.position.distance_to(query.to)>0.5: continue
			var slope := rad_to_deg(acos(clampf(field.normal(point.x,point.y).y,-1,1)))
			var geo := field.region.geographic64(point.x,point.y)
			var added := session.record({"latitude":geo[0],"longitude":geo[1],"kind":"slope_hazard" if slope>=15 else "slope_caution" if slope>=8 else "clear_slope","slope":slope,"source":sample.source,"spacing_m":sample.spacing_m,"description":"DEM-derived simulated scout assessment","local":point,"region":field.region.signature()})
			discovered=discovered or (added and slope>=8)
	for rock: Dictionary in world.result.rocks:
		var delta := Vector2(rock.position.x-p.x,rock.position.z-p.z)
		if delta.length()>10 or delta.normalized().dot(forward)<0.5: continue
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*0.5,rock.position+Vector3.UP*rock.size*0.7,1))
		if hit.is_empty() or hit.position.distance_to(rock.position)>rock.size*2+0.5: continue
		var geo := field.region.geographic64(rock.position.x,rock.position.z)
		discovered=session.record({"latitude":geo[0],"longitude":geo[1],"kind":"simulated_obstacle","description":"SIMULATED OBSTACLE · procedural collision rock","source":"Project-created collision geometry","spacing_m":0,"local":Vector2(rock.position.x,rock.position.z),"region":field.region.signature()}) or discovered
	if discovered: replan()
	if field.cache.size()>4096: field.cache.clear()

func reset() -> void:
	generation+=1; pending=false; elapsed=0; session.reset()
	if has_goal: propose(start,goal)

func _exit_tree() -> void:
	if worker!=null: worker.wait_to_finish()
