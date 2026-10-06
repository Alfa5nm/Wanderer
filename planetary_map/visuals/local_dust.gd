class_name MarsLocalDust
extends Node3D

var world: Node
var atmosphere: MarsAtmosphereProfile
var sheets: CPUParticles3D
var wheels: Array[CPUParticles3D] = []
var material: ShaderMaterial
var wheel_material: ShaderMaterial
var clock := 0.0

func emitter(count: int,size_m: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount=count
	particles.lifetime=14.0
	particles.preprocess=8.0
	particles.local_coords=false
	particles.gravity=Vector3.ZERO
	particles.direction=Vector3(1,0.04,0.25).normalized()
	particles.spread=12
	particles.initial_velocity_min=0.08
	particles.initial_velocity_max=0.16
	particles.scale_amount_min=0.6
	particles.scale_amount_max=1.3
	particles.fixed_fps=20
	particles.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := QuadMesh.new()
	mesh.size=Vector2.ONE*size_m
	particles.mesh=mesh
	var gradient := Gradient.new()
	gradient.offsets=PackedFloat32Array([0,0.20,0.75,1])
	gradient.colors=PackedColorArray([Color(1,1,1,0),Color.WHITE,Color.WHITE,Color(1,1,1,0)])
	particles.color_ramp=gradient
	return particles

func _ready() -> void:
	material=ShaderMaterial.new()
	material.shader=load("res://planetary_map/visuals/drifting_dust.gdshader")
	material.render_priority=10
	material.set_shader_parameter("dust_tint",atmosphere.dust_color)
	sheets=emitter(18,6.0)
	sheets.name="IllustrativeDriftingDust"
	sheets.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX
	sheets.emission_box_extents=Vector3(28,0.6,28)
	sheets.material_override=material
	add_child(sheets)
	wheel_material=material.duplicate()
	wheel_material.set_shader_parameter("opacity",0.10)
	for i in 6:
		var particles := emitter(10,0.28)
		particles.lifetime=2.0
		particles.preprocess=0.0
		particles.emitting=false
		particles.direction=Vector3(0,1,0)
		particles.initial_velocity_min=0.04
		particles.initial_velocity_max=0.09
		particles.material_override=wheel_material
		add_child(particles)
		wheels.append(particles)

func _process(dt: float) -> void:
	if not is_instance_valid(world.rover): return
	var day := atmosphere.daylight(world.patch_lighting.settings.sun_direction.y)
	material.set_shader_parameter("daylight",day)
	wheel_material.set_shader_parameter("daylight",day)
	material.set_shader_parameter("opacity",0.09*atmosphere.strength)
	var available: bool = not world.source_appearance and atmosphere.strength>0.01 and day>0.01
	sheets.visible=available
	sheets.emitting=available
	var count := 10 if atmosphere.quality==0 else (26 if atmosphere.quality==2 else 18)
	if sheets.amount!=count: sheets.amount=count
	var wall_speed := 1.0/maxf(Engine.time_scale,0.001)
	sheets.speed_scale=wall_speed
	for particle in wheels: particle.speed_scale=wall_speed
	clock+=dt*wall_speed
	if clock>0.25:
		clock=0
		var p: Vector3 = world.rover.chassis.global_position
		var camera := get_viewport().get_camera_3d()
		if camera!=null:
			var forward := -camera.global_basis.z
			p+=Vector3(forward.x,0,forward.z).normalized()*22
		sheets.global_position=Vector3(p.x,world.result.field.sample(p.x,p.z).height+1.2,p.z)
	for i in wheels.size():
		var wheel: RigidBody3D = world.rover.wheels[i].body
		wheels[i].visible=available
		wheels[i].global_position=wheel.global_position-Vector3.UP*world.rover.value("wheel_radius")
		wheels[i].emitting=available and wheel.contacts>0 and absf(world.rover.wheels[i].rate)>0.025
