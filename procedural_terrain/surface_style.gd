class_name TerrainSurfaceStyle
extends Resource

## Illustrative material controls. Never consumed by measured geometry or collision.
@export var seed := 7462
@export_range(0,1) var tint_strength := 0.48
@export var dust_color := Color("b47850")
@export var broad_scale_m := 5.0
@export var sand_scale_m := 0.025
@export_range(0,1) var normal_strength := 0.55
@export_range(0,1) var roughness := 0.94
@export_range(0,0.35) var occlusion_strength := 0.18
@export_range(0,1) var specular := 0.06

func signature() -> String:
	return JSON.stringify(["dusty_surface_v1",seed,tint_strength,str(dust_color),broad_scale_m,sand_scale_m,normal_strength,roughness,occlusion_strength,specular]).sha256_text()

func apply(material: ShaderMaterial,source: bool) -> void:
	var sand_path := "res://planetary_map/visuals/assets/sand_normal_roughness.png"
	var rock_path := "res://planetary_map/visuals/assets/rock_normal_roughness.png"
	var sand: Texture2D = load(sand_path) if ResourceLoader.exists(sand_path) else null
	var rock: Texture2D = load(rock_path) if ResourceLoader.exists(rock_path) else null
	material.set_shader_parameter("sand_detail",sand)
	material.set_shader_parameter("rock_detail",rock)
	material.set_shader_parameter("detail_maps_ready",sand!=null and rock!=null)
	material.set_shader_parameter("cinematic",not source)
	material.set_shader_parameter("cosmetic_seed",float(seed%10007))
	material.set_shader_parameter("tint_strength",tint_strength)
	material.set_shader_parameter("dust_color",dust_color)
	material.set_shader_parameter("broad_scale",1.0/maxf(broad_scale_m,0.1))
	material.set_shader_parameter("sand_scale",1.0/maxf(sand_scale_m,0.005))
	material.set_shader_parameter("normal_strength",normal_strength)
	material.set_shader_parameter("base_roughness",roughness)
	material.set_shader_parameter("occlusion_strength",occlusion_strength)
	material.set_shader_parameter("base_specular",specular)
