class_name PlanetLayerManager
extends Node

signal layer_changed(id: String)
var active_id := ""
var layers: Dictionary = {}
var surface: MeshInstance3D

func register_layer(data: PlanetDataLayer) -> void:
	if data != null and not data.id.is_empty(): layers[data.id] = data

func set_view_mode(id: String) -> bool:
	if not layers.has(id) or surface == null: return false
	var data: PlanetDataLayer = layers[id]
	if data.material != null:
		surface.material_override = data.material
	else:
		var material := StandardMaterial3D.new()
		material.roughness = 0.98
		material.metallic_specular = 0.08
		material.albedo_color = Color("b97550")
		if not data.texture_path.is_empty() and ResourceLoader.exists(data.texture_path):
			material.albedo_texture = load(data.texture_path)
			material.albedo_color = Color.WHITE
		else:
			push_warning("Planet layer texture unavailable: " + data.texture_path)
		surface.material_override = material
	active_id = id
	layer_changed.emit(id)
	return true

func available_layers() -> Array[String]:
	var ids: Array[String] = []
	for id in layers:
		var data: PlanetDataLayer = layers[id]
		if data.material != null or ResourceLoader.exists(data.texture_path): ids.append(id)
	return ids
