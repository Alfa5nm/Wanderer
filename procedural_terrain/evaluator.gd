class_name TerrainGraphEvaluator
extends RefCounted

var cache: Dictionary = {}
var graph: TerrainGenerationGraph
var context: Dictionary
var values: Dictionary
var hashes: Dictionary
var visiting: Dictionary
var evaluated: PackedStringArray
var hits: PackedStringArray
var errors: PackedStringArray
var disk_hits: PackedStringArray
var artifacts := TerrainArtifactCache.new()
const REVISION := "local-terrain-horizon-5"

func evaluate(source_graph: TerrainGenerationGraph,ctx: Dictionary) -> TerrainPatchResult:
	var started = Time.get_ticks_usec()
	graph=source_graph; context=ctx; values={}; hashes={}; visiting={}
	evaluated=PackedStringArray(); hits=PackedStringArray(); errors=PackedStringArray(); disk_hits=PackedStringArray()
	var result = TerrainPatchResult.new()
	result.region=context.region
	if not result.region.valid():
		result.warnings.append("Invalid geographic mission bounds")
		return result
	var ids = {}
	for item in graph.nodes:
		if item==null or item.id.is_empty() or ids.has(item.id):
			errors.append("Missing or duplicate graph node identifier")
			break
		ids[item.id]=true
	if errors.is_empty():
		var chunks = resolve("collision")
		if chunks is Array: result.chunks=chunks
		result.field=resolve("height") as TerrainHeightField
		if result.field!=null:
			for chunk in result.chunks: result.field.sources.merge(chunk.get("source_inventory",{}),true)
		var imagery = resolve("imagery")
		if imagery is Dictionary:
			result.image=imagery.image
			result.scenery_image=imagery.scenery_image
			result.image_sources=imagery.sources
		# Shading/scatter are optional: failures retain the sourced material and geometry.
		if graph.node("shading")!=null:
			var before: PackedStringArray = errors.duplicate()
			var shading = resolve("shading")
			if shading is Dictionary and shading.get("image",null) is Image:
				result.cavity_image=shading.image
				result.field.sources.merge(shading.get("source_inventory",{}),true)
			else: result.warnings.append("Cavity preparation unavailable; basic source material retained")
			errors=before
		if graph.node("gravel")!=null:
			var before: PackedStringArray = errors.duplicate()
			var stones = resolve("gravel")
			if stones is Array: result.gravel=stones
			else: result.warnings.append("Cosmetic gravel unavailable")
			errors=before
		var rocks = resolve("rocks")
		if rocks is Array: result.rocks=rocks
		var route = resolve("route")
		if route is Dictionary: result.route=route
	result.warnings.append_array(errors)
	result.evaluated=evaluated
	result.cache_hits=hits
	result.disk_hits=disk_hits
	result.hashes=hashes.duplicate()
	result.hashes["style"]=graph.surface_style.signature()
	if result.field!=null: result.sources=result.field.sources.duplicate()
	for data: PlanetDataset in context.service.datasets:
		if data.kind=="elevation" and result.sources.has(data.title):
			result.elevation_sources.append({"title":data.title,"product":data.product_id,"spacing_m":data.prepared_spacing_m,"source_spacing_m":data.source_spacing_m,"datum":data.vertical_datum,"url":data.source_url,"accuracy":data.accuracy_note,"dates":data.observation_dates})
	context.global_image=null
	result.valid=errors.is_empty() and not result.chunks.is_empty() and result.field!=null and result.image!=null
	result.build_ms=float(Time.get_ticks_usec()-started)/1000.0
	return result

func resolve(id: String) -> Variant:
	if values.has(id): return values[id]
	if visiting.has(id): errors.append("Graph cycle at "+id); return null
	var item = graph.node(id)
	if item==null: errors.append("Missing graph node "+id); return null
	var ports = TerrainGraphNode.ports(item.operation)
	if ports.is_empty() or item.execution!="runtime_cpu": errors.append("Unsupported node "+id); return null
	visiting[id]=true
	var args = {}
	var dependencies = {}
	for port in ports:
		if port=="out": continue
		var upstream = graph.node(str(item.inputs.get(port,"")))
		if upstream==null or TerrainGraphNode.ports(upstream.operation).get("out","")!=ports[port]:
			errors.append("Invalid typed connection: "+id+"."+port)
			visiting.erase(id)
			return null
		args[port]=resolve(upstream.id)
		dependencies[port]=hashes.get(upstream.id,"")
	if not errors.is_empty(): visiting.erase(id); return null
	var source_key = ""
	if item.operation=="Region": source_key=context.region.signature()
	if item.operation=="Height Field": source_key=context.elevation_version
	if item.operation=="Imagery": source_key=context.imagery_version
	var digest = JSON.stringify([REVISION,item.operation,item.parameters,dependencies,source_key]).sha256_text()
	hashes[id]=digest
	var value: Variant
	if cache.has(id) and cache[id].hash==digest:
		value=cache[id].value
		hits.append(id)
	else:
		var persistent: bool = item.operation in ["Displace","Normals","Collision","Imagery","Cavity"]
		value=artifacts.read(digest) if persistent else null
		if value!=null: hits.append(id); disk_hits.append(id)
		else:
			value=execute(item,args)
			if value!=null:
				evaluated.append(id)
				if persistent: artifacts.write(digest,value)
		if value==null: errors.append("Generation failed at "+id)
		else: cache[id]={"hash":digest,"value":value}
	visiting.erase(id)
	values[id]=value
	return value

func execute(item: TerrainGraphNode,args: Dictionary) -> Variant:
	match item.operation:
		"Region": return context.region
		"Height Field":
			var field = TerrainHeightField.new()
			field.region=args.region; field.service=context.service
			return field
		"Grid":
			var spacing = float(item.parameters.get("spacing_m",4))
			var chunk = float(item.parameters.get("chunk_m",64))
			if not is_finite(spacing) or not is_finite(chunk) or spacing<1 or spacing>16 or chunk<32 or chunk>128: return null
			return {"region":args.region,"chunk_m":chunk,"cells":clampi(int(ceil(chunk/spacing)),2,128)}
		"Displace": return geometry(args.field,args.grid)
		"Normals": return geometry_normals(args.geometry,args.field)
		"Collision":
			var chunks: Array = []
			for chunk in args.geometry:
				var output: Dictionary = chunk.duplicate()
				var faces = PackedVector3Array()
				if not chunk.get("scenery",false):
					for index in chunk.arrays[Mesh.ARRAY_INDEX]: faces.append(chunk.arrays[Mesh.ARRAY_VERTEX][index])
				output["faces"]=faces
				chunks.append(output)
			return chunks
		"Imagery":
			if context.global_image==null:
				var base := Image.new()
				if base.load_jpg_from_buffer(FileAccess.get_file_as_bytes("res://planetary_map/assets/mars_viking_4k.jpg"))==OK: context.global_image=base
			var main = imagery(args.region,clampi(int(item.parameters.get("pixels",512)),64,1024),args.region.terrain_bounds())
			var far = imagery(args.region,256,args.region.terrain_bounds().grow(20000))
			main["scenery_image"]=far.image
			for source in far.sources:
				if not main.sources.has(source): main.sources.append(source)
			return main
		"Cavity": return cavity(args.field,item.parameters)
		"Gravel": return gravel(args.field,item.parameters)
		"Scatter": return scatter(args.field,item.parameters)
		"Route": return route(args.field,args.rocks,item.parameters)
	return null

func geometry(field: TerrainHeightField,grid: Dictionary) -> Array:
	var chunks: Array = []
	var bounds = field.region.terrain_bounds()
	var count = Vector2i(ceili(bounds.size.x/grid.chunk_m),ceili(bounds.size.y/grid.chunk_m))
	var chunk_size = bounds.size/Vector2(count)
	var cells: int = grid.cells
	for cy in count.y:
		for cx in count.x:
			var origin = bounds.position+Vector2(cx,cy)*chunk_size
			var vertices = PackedVector3Array()
			var uvs = PackedVector2Array()
			var indices = PackedInt32Array()
			for y in range(cells+1):
				for x in range(cells+1):
					# Global lattice coordinates make shared edge samples bit-identical.
					var point = bounds.position+Vector2(cx*cells+x,cy*cells+y)*chunk_size/cells
					var sample = field.sample(point.x,point.y)
					if not sample.valid: errors.append("No valid elevation at "+str(sample.geo)); return []
					vertices.append(Vector3(point.x-origin.x,sample.height,point.y-origin.y))
					uvs.append((point-bounds.position)/bounds.size)
			for y in cells:
				for x in cells:
					var a = y*(cells+1)+x
					indices.append_array(PackedInt32Array([a,a+1,a+cells+1,a+1,a+cells+2,a+cells+1]))
			var arrays = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_TEX_UV]=uvs; arrays[Mesh.ARRAY_INDEX]=indices
			chunks.append({"id":Vector2i(cx,cy),"origin":Vector3(origin.x,0,origin.y),"arrays":arrays,"attributes":{},"bounds":Rect2(origin,chunk_size)})
	# A coarse sourced annulus extends scenery without changing the playable area.
	var segments: int = mini(128,maxi(count.x,count.y)*cells)
	var outer: Rect2 = bounds.grow(20000)
	for edge in 4:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		for row in range(17):
			var t := float(row)/16
			var ring: Rect2 = bounds.grow(20000*t*t)
			for column in range(segments+1):
				var u := float(column)/segments
				var point := Vector2(lerpf(ring.position.x,ring.end.x,u),ring.position.y)
				if edge==1: point=Vector2(ring.end.x,lerpf(ring.position.y,ring.end.y,u))
				if edge==2: point=Vector2(lerpf(ring.end.x,ring.position.x,u),ring.end.y)
				if edge==3: point=Vector2(ring.position.x,lerpf(ring.end.y,ring.position.y,u))
				var value := field.sample(point.x,point.y)
				vertices.append(Vector3(point.x,value.height,point.y))
				uvs.append((point-outer.position)/outer.size)
		for row in 16:
			for column in segments:
				var index := row*(segments+1)+column
				indices.append_array(PackedInt32Array([index,index+segments+1,index+1,index+1,index+segments+1,index+segments+2]))
		arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_TEX_UV]=uvs; arrays[Mesh.ARRAY_INDEX]=indices
		chunks.append({"id":Vector2i(-1,edge),"origin":Vector3.ZERO,"arrays":arrays,"attributes":{},"scenery":true,"bounds":outer})
	for chunk in chunks: chunk["source_inventory"]=field.sources.duplicate()
	return chunks

func geometry_normals(input: Array,field: TerrainHeightField) -> Array:
	var chunks: Array = []
	for chunk in input:
		var output: Dictionary = chunk.duplicate()
		var arrays: Array = chunk.arrays.duplicate()
		var normals = PackedVector3Array()
		var slopes = PackedFloat32Array()
		var curvature = PackedFloat32Array()
		for vertex in arrays[Mesh.ARRAY_VERTEX]:
			var point: Vector3 = vertex+chunk.origin
			var normal = field.normal(point.x,point.z)
			normals.append(normal)
			slopes.append(rad_to_deg(acos(clampf(normal.y,-1,1))))
			curvature.append(field.curvature(point.x,point.z))
		arrays[Mesh.ARRAY_NORMAL]=normals
		output["arrays"]=arrays
		output["attributes"]={"slope_degrees":slopes,"curvature_per_m":curvature,"height_m":arrays[Mesh.ARRAY_VERTEX]}
		chunks.append(output)
	for chunk in chunks: chunk["source_inventory"]=field.sources.duplicate()
	return chunks

func imagery(region: TerrainMissionRegion,pixels: int,bounds: Rect2) -> Dictionary:
	var image = Image.create(pixels,pixels,false,Image.FORMAT_RGBA8)
	var sources = {}
	var datasets: Array = context.images
	for y in pixels:
		for x in pixels:
			var p = bounds.position+bounds.size*Vector2((x+0.5)/pixels,(y+0.5)/pixels)
			var ll = region.geographic64(p.x,p.y)
			var color = Color("81563e")
			var global: Image = context.global_image
			if global!=null:
				var uv = PlanetCoordinates.lat_lon_to_uv(ll[0],ll[1])
				color=global.get_pixel(clampi(int(uv.x*global.get_width()),0,global.get_width()-1),clampi(int(uv.y*global.get_height()),0,global.get_height()-1))
			for data: PlanetDataset in datasets:
				if not data.imagery_valid(ll[0],ll[1]): continue
				var fx = clampf((ll[1]-data.bounds.position.x)/data.bounds.size.x*data.width-0.5,0,data.width-1)
				var fy = clampf((data.bounds.end.y-ll[0])/data.bounds.size.y*data.height-0.5,0,data.height-1)
				var ix = int(fx); var iy := int(fy)
				var ix1 = mini(ix+1,data.width-1); var iy1 := mini(iy+1,data.height-1)
				var a = data.image.get_pixel(ix,iy); var b := data.image.get_pixel(ix1,iy)
				var c = data.image.get_pixel(ix,iy1); var d := data.image.get_pixel(ix1,iy1)
				# Internal validity is independent of visual edge feathering.
				if data.validity_bits.is_empty() and minf(minf(a.a,b.a),minf(c.a,d.a))<=0: continue
				var valid_neighbors := true
				if not data.validity_bits.is_empty():
					for neighbor in [Vector2i(ix,iy),Vector2i(ix1,iy),Vector2i(ix,iy1),Vector2i(ix1,iy1)]:
						var pixel: int = neighbor.y*data.width+neighbor.x
						valid_neighbors=valid_neighbors and (data.validity_bits[pixel/8] & (1<<(pixel%8)))!=0
				if not valid_neighbors: continue
				var value = a.lerp(b,fx-ix).lerp(c.lerp(d,fx-ix),fy-iy)
				var edge_posts = minf(minf(fx,data.width-1-fx),minf(fy,data.height-1-fy))
				var weight = smoothstep(0.0,4.0,edge_posts) if not data.validity_bits.is_empty() else value.a
				color=color.lerp(Color(value.r,value.g,value.b,1),weight)
				sources[data.id]={"title":data.title,"product":data.product_id,"spacing_m":data.prepared_spacing_m,"source_spacing_m":data.source_spacing_m,"url":data.source_url,"accuracy":data.accuracy_note,"dates":data.observation_dates,"classification":data.metadata.get("color_type","See product label; imagery retains baked illumination")}
			image.set_pixel(x,y,Color(color.r,color.g,color.b,1))
	image.generate_mipmaps()
	return {"image":image,"sources":sources.values()}

func scatter(field: TerrainHeightField,parameters: Dictionary) -> Array:
	var points: Array = []
	var rng = RandomNumberGenerator.new()
	rng.seed=int(parameters.get("seed",field.region.seed))
	var bounds = field.region.playable_bounds()
	var count = clampi(int(bounds.get_area()*clampf(float(parameters.get("density",0.0005)),0,0.002)),0,128)
	for i in count:
		var x = rng.randf_range(bounds.position.x,bounds.end.x)
		var z = rng.randf_range(bounds.position.y,bounds.end.y)
		var size = rng.randf_range(0.15,0.5)
		if Vector2(x,z).length()<float(parameters.get("exclusion_m",8)) or field.normal(x,z).y<cos(deg_to_rad(25)): continue
		var value = field.sample(x,z)
		if value.valid: points.append({"position":Vector3(x,value.height,z),"size":size,"rotation":rng.randf()*TAU,"shape":Vector3(rng.randf_range(0.8,1.2),rng.randf_range(0.55,0.95),rng.randf_range(0.8,1.2))})
	return points

func route(field: TerrainHeightField,rocks: Array,parameters: Dictionary) -> Dictionary:
	var points: Array = parameters.get("points",[])
	var vertices = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	var warnings: PackedStringArray = []
	var width = clampf(float(parameters.get("width_m",0.8)),0.2,4)
	if points.size()<2: return {"arrays":[],"warnings":warnings,"origin":parameters.get("origin","none")}
	for segment in range(1,points.size()):
		var a: Vector2 = points[segment-1]; var b: Vector2 = points[segment]
		var count = clampi(ceili(a.distance_to(b)/2),1,1024)
		var side = Vector2(-(b-a).y,(b-a).x).normalized()*width*0.5
		for i in count:
			var p = a.lerp(b,float(i)/count); var q := a.lerp(b,float(i+1)/count)
			var blocked = not field.region.playable_bounds().has_point(p) or not field.region.playable_bounds().has_point(q) or field.normal(p.x,p.y).y<cos(deg_to_rad(35))
			for rock in rocks:
				if Vector2(rock.position.x,rock.position.z).distance_to(p)<rock.size+width: blocked=true
			if blocked:
				if not warnings.has("Path interrupted at a boundary, steep terrain or procedural obstacle"): warnings.append("Path interrupted at a boundary, steep terrain or procedural obstacle")
				continue
			var start = vertices.size()
			for point in [p-side,p+side,q-side,q+side]:
				var value = field.sample(point.x,point.y)
				vertices.append(Vector3(point.x,value.height+0.07,point.y))
			var u0 = (segment-1+float(i)/count)/(points.size()-1)
			var u1 = (segment-1+float(i+1)/count)/(points.size()-1)
			uvs.append_array(PackedVector2Array([Vector2(u0,0),Vector2(u0,1),Vector2(u1,0),Vector2(u1,1)]))
			indices.append_array(PackedInt32Array([start,start+1,start+2,start+1,start+3,start+2]))
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_TEX_UV]=uvs; arrays[Mesh.ARRAY_INDEX]=indices
	return {"arrays":arrays,"warnings":warnings,"origin":parameters.get("origin","unknown")}


func cavity(field: TerrainHeightField,parameters: Dictionary) -> Dictionary:
	var pixels: int = clampi(int(parameters.get("pixels",128)),32,256)
	var bounds: Rect2 = field.region.terrain_bounds()
	var heights := PackedFloat32Array()
	heights.resize(pixels*pixels)
	for y in pixels:
		for x in pixels:
			var p: Vector2 = bounds.position+bounds.size*Vector2(float(x)/(pixels-1),float(y)/(pixels-1))
			var value := field.sample(p.x,p.y)
			if not value.valid: return {}
			heights[y*pixels+x]=value.height
	var image := Image.create(pixels,pixels,false,Image.FORMAT_RGBA8)
	var step: float = maxf(bounds.size.x,bounds.size.y)/(pixels-1)
	for y in pixels:
		for x in pixels:
			var blocked := 0.0
			for direction in 8:
				var unit := Vector2(cos(direction*TAU/8),sin(direction*TAU/8))
				var horizon := 0.0
				for radius in [1,2,4,8]:
					var ix := clampi(roundi(x+unit.x*radius),0,pixels-1)
					var iy := clampi(roundi(y+unit.y*radius),0,pixels-1)
					var distance := Vector2(ix-x,iy-y).length()*step
					if distance>0: horizon=maxf(horizon,(heights[iy*pixels+ix]-heights[y*pixels+x])/distance)
				blocked+=sin(atan(horizon))
			image.set_pixel(x,y,Color(clampf(blocked/8,0,1),0,0,1))
	image.generate_mipmaps()
	return {"image":image,"bounds":bounds,"source_inventory":field.sources.duplicate(),"derivation":"Eight-direction horizon cavity from measured elevations; not measured albedo"}

func gravel(field: TerrainHeightField,parameters: Dictionary) -> Array:
	var output: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed=int(parameters.get("seed",field.region.seed))+1987
	var bounds: Rect2 = field.region.playable_bounds()
	var count: int = clampi(int(parameters.get("count",4096)),0,8192)
	for index in count:
		var p := Vector2(rng.randf_range(bounds.position.x,bounds.end.x),rng.randf_range(bounds.position.y,bounds.end.y))
		var value := field.sample(p.x,p.y)
		if not value.valid: continue
		var size := rng.randf_range(0.015,0.07)
		output.append({"position":Vector3(p.x,value.height,p.y),"size":size,"rotation":rng.randf()*TAU,"shape":Vector3(rng.randf_range(0.8,1.5),rng.randf_range(0.35,0.75),rng.randf_range(0.8,1.4))})
	return output
