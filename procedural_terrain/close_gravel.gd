class_name MarsCloseGravel
extends Node3D

# Stable geographic scatter, streamed one small tile per rendered frame.
var world: Node
var tiles: Dictionary = {}
var field: TerrainHeightField
var stone: SphereMesh

func _ready() -> void:
	name="IllustrativeNearGravel"
	field=TerrainHeightField.new()
	field.service=world.service
	field.region=world.result.region
	stone=SphereMesh.new()
	stone.radius=1; stone.height=2; stone.radial_segments=8; stone.rings=3

func _process(_dt: float) -> void:
	visible=not world.source_appearance and (world.recording==null or world.recording.stage==0)
	if not visible: return
	var camera := get_viewport().get_camera_3d()
	if camera==null: return
	var center := Vector2i(floori(camera.global_position.x/8),floori(camera.global_position.z/8))
	for key: Vector2i in tiles.keys():
		if absi(key.x-center.x)>1 or absi(key.y-center.y)>1:
			tiles[key].queue_free()
			tiles.erase(key)
	for y in range(-1,2):
		for x in range(-1,2):
			var key := center+Vector2i(x,y)
			if tiles.has(key): continue
			make_tile(key)
			return

func make_tile(key: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=hash([key.x,key.y,world.graph.surface_style.seed])
	var instances := MultiMesh.new()
	instances.transform_format=MultiMesh.TRANSFORM_3D
	instances.mesh=stone
	instances.instance_count=120
	for i in 120:
		var x := key.x*8+rng.randf()*8
		var z := key.y*8+rng.randf()*8
		var sample := field.sample(x,z)
		var size := rng.randf_range(0.012,0.055)
		var shape := Vector3(size,size*rng.randf_range(0.35,0.70),size*rng.randf_range(0.65,1.2))
		var basis := Basis(Quaternion(Vector3.UP,field.normal(x,z)))*Basis(Vector3.UP,rng.randf()*TAU)
		instances.set_instance_transform(i,Transform3D(basis.scaled(shape),Vector3(x,float(sample.height)+shape.y*0.5,z)))
	var visual := MultiMeshInstance3D.new()
	visual.multimesh=instances
	visual.material_override=world.gravel_material
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(visual)
	tiles[key]=visual
	field.cache.clear()
