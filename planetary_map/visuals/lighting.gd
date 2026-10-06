class_name PlanetLighting
extends Node

@export var settings := PlanetVisualSettings.new()
var sun: DirectionalLight3D
var environment: Environment
var sky_material: ShaderMaterial
var rig: PlanetCameraRig
var terrain: PlanetTerrainRenderer
var local_surface := false
var haze: MeshInstance3D
var base_altitude_m := 0.0
var native_fog_requested := true

func supports_native_fog() -> bool:
	return RenderingServer.get_current_rendering_method()=="forward_plus"

func set_native_fog(enabled: bool) -> void:
	native_fog_requested=enabled
	update_atmosphere()

func _ready() -> void:
	var saved: Dictionary = get_tree().root.get_meta("mars_appearance",{})
	if not saved.is_empty():
		settings.atmosphere.strength=float(saved.get("strength",1.35))
		settings.atmosphere.quality=int(saved.get("quality",1))
	environment=Environment.new()
	environment.background_mode=Environment.BG_SKY
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_DISABLED
	environment.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_exposure=settings.exposure
	sky_material=ShaderMaterial.new()
	sky_material.shader=load("res://planetary_map/visuals/space.gdshader")
	sky_material.set_shader_parameter("sun_direction",settings.sun_direction)
	sky_material.set_shader_parameter("sun_color",settings.sun_color)
	sky_material.set_shader_parameter("solar_radius",deg_to_rad(settings.solar_diameter_degrees)*0.5)
	sky_material.set_shader_parameter("star_intensity",settings.star_intensity)
	var sky := Sky.new()
	sky.sky_material=sky_material
	sky.process_mode=Sky.PROCESS_MODE_INCREMENTAL
	environment.sky=sky
	var world := WorldEnvironment.new()
	world.environment=environment
	add_child(world)
	sun=DirectionalLight3D.new()
	sun.light_color=settings.sun_color
	sun.light_energy=settings.sun_energy
	sun.shadow_enabled=true
	sun.shadow_bias=0.02
	add_child(sun)
	sun.look_at(-settings.sun_direction,Vector3.UP)
	get_viewport().msaa_3d=Viewport.MSAA_2X
	environment.glow_enabled=true
	environment.glow_intensity=0.12
	environment.glow_bloom=0.0
	environment.glow_hdr_threshold=1.5
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white=6.0
	settings.atmosphere.apply(sky_material)

func configure_surface(altitude: float) -> void:
	local_surface=true
	base_altitude_m=altitude
	sky_material.shader=load("res://planetary_map/visuals/surface_sky.gdshader")
	sky_material.set_shader_parameter("altitude_m",altitude)
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution=1.0
	environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	environment.ssao_enabled=true
	environment.ssao_radius=0.65
	environment.ssao_intensity=0.45
	haze=MeshInstance3D.new()
	haze.name="DustAerialPerspective"
	var quad := QuadMesh.new()
	quad.size=Vector2(2,2)
	haze.mesh=quad
	haze.extra_cull_margin=100000
	haze.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	haze.material_override=ShaderMaterial.new()
	haze.material_override.shader=load("res://planetary_map/visuals/surface_haze.gdshader")
	haze.material_override.render_priority=100
	haze.material_override.set_shader_parameter("base_altitude_m",altitude)
	add_child(haze)
	update_atmosphere()

func update_atmosphere() -> void:
	settings.atmosphere.apply(sky_material)
	if haze!=null: settings.atmosphere.apply(haze.material_override)
	if terrain!=null and terrain.atmosphere!=null:
		settings.atmosphere.apply(terrain.atmosphere.material_override)
	get_viewport().msaa_3d=Viewport.MSAA_4X if settings.atmosphere.quality==2 else Viewport.MSAA_2X
	environment.glow_enabled=settings.atmosphere.quality>0
	if local_surface:
		environment.ssao_enabled=settings.atmosphere.quality>0
		set_direction(settings.sun_direction)

func set_direction(direction: Vector3) -> void:
	settings.sun_direction=direction.normalized()
	sun.look_at(-settings.sun_direction,Vector3.FORWARD if absf(settings.sun_direction.y)>0.99 else Vector3.UP)
	sky_material.set_shader_parameter("sun_direction",settings.sun_direction)
	if local_surface:
		var day := settings.atmosphere.daylight(settings.sun_direction.y)
		sun.light_energy=settings.sun_energy if settings.sun_direction.y>0 else 0.0
		environment.ambient_light_energy=settings.atmosphere.daylight_fill*day*minf(settings.atmosphere.strength,1.0)
		haze.material_override.set_shader_parameter("sun_direction",settings.sun_direction)
		# Native fog is opt-in through the separate Forward+ launch, never enabled in GL.
		var native := supports_native_fog() and native_fog_requested and settings.atmosphere.quality>0
		environment.volumetric_fog_enabled=native
		if native:
			environment.volumetric_fog_density=0.00018*settings.atmosphere.strength*day
			environment.volumetric_fog_albedo=settings.atmosphere.dust_color
			environment.volumetric_fog_emission=Color.BLACK
			environment.volumetric_fog_anisotropy=0.65
			environment.volumetric_fog_length=1500.0 if settings.atmosphere.quality==1 else 2500.0
			environment.volumetric_fog_detail_spread=2.0
			environment.volumetric_fog_ambient_inject=0.25*day
			environment.volumetric_fog_sky_affect=0.0
			environment.volumetric_fog_temporal_reprojection_enabled=true
			environment.volumetric_fog_temporal_reprojection_amount=0.85
		# Retain Mars-specific distant scattering without adding two full haze layers.
		haze.material_override.set_shader_parameter("haze_weight",0.35 if native else 1.0)

func configure(camera_rig: PlanetCameraRig, renderer: PlanetTerrainRenderer) -> void:
	rig=camera_rig
	terrain=renderer

func _process(_dt: float) -> void:
	if local_surface:
		var camera := get_viewport().get_camera_3d()
		if camera!=null:
			var height := base_altitude_m+camera.global_position.y
			if absf(height-float(sky_material.get_shader_parameter("altitude_m")))>20:
				sky_material.set_shader_parameter("altitude_m",height)
	if rig==null: return
	var clearance := maxf(rig.distance-rig.radius,0.000025)*PlanetCameraRig.RENDER_SCALE
	sun.directional_shadow_max_distance=clampf(clearance*8.0,1.0,300.0)
	sun.shadow_enabled=rig.distance/rig.radius<1.06
