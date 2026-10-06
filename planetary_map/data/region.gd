class_name PlanetRegion
extends PlanetMarkerData

# Geographic focus anchor, not an asserted crater boundary.
@export var focus_extent_degrees: float = 1.3
@export_file("*.tscn") var deployment_scene: String = "res://main.tscn"
@export var deployment_label: String = "Curiosity mobility field lab"

# Optional external scene dependencies; held in memory before scene activation.
@export var preload_paths: PackedStringArray
