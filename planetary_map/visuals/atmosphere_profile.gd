class_name MarsAtmosphereProfile
extends Resource

## Illustrative dust, not a reconstruction of observed Martian weather.
@export_range(0,3) var strength := 1.35
@export var scale_height_m := 10500.0
@export var top_height_m := 85000.0
@export var extinction_per_m := 0.000085
@export var dust_color := Color("c4a286")
@export_range(0,0.9) var anisotropy := 0.65
@export var near_clear_m := 45.0
@export var daylight_fill := 0.16
@export var quality := 1
const TRANSPORT_PATH = "res://planetary_map/visuals/assets/dust_transport.png"

func daylight(sun_height: float) -> float:
	return smoothstep(-0.12,0.08,sun_height)

func apply(material: ShaderMaterial) -> void:
	var table: Texture2D = load(TRANSPORT_PATH) if ResourceLoader.exists(TRANSPORT_PATH) else null
	material.set_shader_parameter("dust_transport",table)
	material.set_shader_parameter("has_dust_transport",table!=null)
	material.set_shader_parameter("atmosphere_strength",strength)
	material.set_shader_parameter("dust_color",dust_color)
	material.set_shader_parameter("dust_g",anisotropy)
	material.set_shader_parameter("scale_height_m",scale_height_m)
	material.set_shader_parameter("extinction_per_m",extinction_per_m)
	material.set_shader_parameter("near_clear_m",near_clear_m)
	material.set_shader_parameter("sample_count",4 if quality==0 else 8)
