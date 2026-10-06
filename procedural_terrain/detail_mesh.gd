class_name TerrainDetailMesh
extends RefCounted

## Canonical boundary anchors are the unchanged base mesh's edge samples.
## Extra boundary vertices let even a coarse interior meet those anchors exactly.
static func grid_sample(arrays: Array,cells: int,uv: Vector2) -> Dictionary:
	var x: float = clampf(uv.x,0,1)*cells
	var y: float = clampf(uv.y,0,1)*cells
	var ix: int = mini(int(x),cells-1)
	var iy: int = mini(int(y),cells-1)
	var tx: float = x-ix
	var ty: float = y-iy
	var a: int = iy*(cells+1)+ix
	var indices: Array = [a,a+1,a+cells+1] if tx+ty<=1 else [a+1,a+cells+2,a+cells+1]
	var weights: Array = [1-tx-ty,tx,ty] if tx+ty<=1 else [1-ty,tx+ty-1,1-tx]
	var height := 0.0
	var normal := Vector3.ZERO
	for i in 3:
		height+=arrays[Mesh.ARRAY_VERTEX][indices[i]].y*weights[i]
		normal+=arrays[Mesh.ARRAY_NORMAL][indices[i]]*weights[i]
	return {"height":height,"normal":normal.normalized()}

static func vertex(field: TerrainHeightField,base: Dictionary,uv: Vector2) -> Dictionary:
	var bounds: Rect2 = base.bounds
	var p: Vector2 = bounds.position+bounds.size*uv
	if uv.x<=0 or uv.y<=0 or uv.x>=1 or uv.y>=1:
		var canonical := grid_sample(base.arrays,int(base.cells),uv)
		return {"point":Vector3(p.x-base.origin.x,canonical.height,p.y-base.origin.z),"normal":canonical.normal}
	var value := field.sample(p.x,p.y)
	if not value.valid: return {}
	return {"point":Vector3(p.x-base.origin.x,value.height,p.y-base.origin.z),"normal":field.normal(p.x,p.y)}

static func build(field: TerrainHeightField,base: Dictionary,cells: int) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var bounds: Rect2 = base.bounds
	var atlas: Rect2 = field.region.terrain_bounds()
	for y in range(cells+1):
		for x in range(cells+1):
			var uv := Vector2(float(x)/cells,float(y)/cells)
			var value := vertex(field,base,uv)
			if value.is_empty(): return {}
			vertices.append(value.point); normals.append(value.normal)
			uvs.append((bounds.position+bounds.size*uv-atlas.position)/atlas.size)
	for y in cells:
		for x in cells:
			var a: int = y*(cells+1)+x
			if cells>=int(base.cells) or (x>0 and y>0 and x<cells-1 and y<cells-1):
				indices.append_array(PackedInt32Array([a,a+1,a+cells+1,a+1,a+cells+2,a+cells+1]))
				continue
			# Fan the outer cell perimeter to canonical samples, including corner cells.
			var corners: Array[Vector2] = [Vector2(x,y),Vector2(x+1,y),Vector2(x+1,y+1),Vector2(x,y+1)]
			var perimeter: Array[int] = []
			for side in 4:
				var start: Vector2 = corners[side]/cells
				var end: Vector2 = corners[(side+1)%4]/cells
				var boundary: bool = (start.x==end.x and (start.x==0 or start.x==1)) or (start.y==end.y and (start.y==0 or start.y==1))
				var segments: int = maxi(1,int(base.cells)/cells) if boundary else 1
				for j in segments:
					var uv: Vector2 = start.lerp(end,float(j)/segments)
					var value := vertex(field,base,uv)
					if value.is_empty(): return {}
					perimeter.append(vertices.size())
					vertices.append(value.point); normals.append(value.normal)
					uvs.append((bounds.position+bounds.size*uv-atlas.position)/atlas.size)
			var center_uv := Vector2(x+0.5,y+0.5)/cells
			var center := vertex(field,base,center_uv)
			if center.is_empty(): return {}
			var center_id: int = vertices.size()
			vertices.append(center.point); normals.append(center.normal)
			uvs.append((bounds.position+bounds.size*center_uv-atlas.position)/atlas.size)
			for j in perimeter.size(): indices.append_array(PackedInt32Array([center_id,perimeter[j],perimeter[(j+1)%perimeter.size()]]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uvs; arrays[Mesh.ARRAY_INDEX]=indices
	return {"id":base.id,"origin":base.origin,"bounds":bounds,"cells":cells,"arrays":arrays}

static func previous_shape(target: Dictionary,old: Dictionary) -> Array:
	var vertices: PackedVector3Array = target.arrays[Mesh.ARRAY_VERTEX].duplicate()
	var normals: PackedVector3Array = target.arrays[Mesh.ARRAY_NORMAL].duplicate()
	var bounds: Rect2 = target.bounds
	for i in vertices.size():
		var uv: Vector2 = (Vector2(vertices[i].x+target.origin.x,vertices[i].z+target.origin.z)-bounds.position)/bounds.size
		# Canonical boundaries never morph; all neighbors retain these exact lines.
		if uv.x<0.000001 or uv.y<0.000001 or uv.x>0.999999 or uv.y>0.999999: continue
		var sample := grid_sample(old.arrays,int(old.cells),uv)
		vertices[i].y=sample.height
		normals[i]=sample.normal
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	return arrays

static func errors(field: TerrainHeightField,base: Dictionary) -> Array[float]:
	var output: Array[float] = [0.0]
	var bounds: Rect2 = base.bounds
	for cells in [32,16,8,4]:
		var maximum := 0.0
		for y in cells:
			for x in cells:
				var p: Vector2 = bounds.position+bounds.size*Vector2(x+0.5,y+0.5)/cells
				var a: Vector2 = bounds.position+bounds.size*Vector2(x+1,y)/cells
				var b: Vector2 = bounds.position+bounds.size*Vector2(x,y+1)/cells
				var h: float = field.sample(p.x,p.y).height
				var approximated: float = (field.sample(a.x,a.y).height+field.sample(b.x,b.y).height)*0.5
				maximum=maxf(maximum,absf(h-approximated))
		output.append(maximum)
	# Monotone conservative envelope; finer grids never get a larger error estimate.
	for i in range(1,output.size()): output[i]=maxf(output[i],output[i-1])
	return output
