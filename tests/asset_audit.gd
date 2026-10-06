extends SceneTree

func _initialize() -> void:
	call_deferred("audit")

func audit() -> void:
	var g: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/geometry.json"))
	var asset: Node3D=load("res://assets/curiosity.glb").instantiate()
	root.add_child(asset)
	var result := {"groups":[],"wheels":[],"triangles":0,"meshes":0,"pass":true}
	for key in g.groups:
		var node:=asset.find_child(key,true,false) as Node3D
		var expected:=Vector3(g.groups[key][0],g.groups[key][1],g.groups[key][2])
		var error: float=node.global_position.distance_to(expected) if node else INF
		result.groups.append({"name":key,"origin_error_m":error})
		if error>0.00001: result["pass"]=false
	for mesh in asset.find_children("*","MeshInstance3D",true,false):
		result.meshes+=1
		for s in mesh.mesh.get_surface_count():
			var arrays: Array=mesh.mesh.surface_get_arrays(s)
			result.triangles+=arrays[Mesh.ARRAY_INDEX].size()/3 if arrays[Mesh.ARRAY_INDEX]!=null else arrays[Mesh.ARRAY_VERTEX].size()/3
		if str(mesh.name).begins_with("wheel_"):
			var bounds: AABB=mesh.get_aabb()
			result.wheels.append({"name":mesh.name,"width_m":bounds.size.x,"diameter_y_m":bounds.size.y,"diameter_z_m":bounds.size.z})
			if absf(bounds.size.x-.4)>.001 or absf(bounds.size.y-.5)>.001 or absf(bounds.size.z-.5)>.001: result["pass"]=false
	var f:=FileAccess.open("res://evidence/reimport_audit.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result))
	quit(0 if result["pass"] else 1)
