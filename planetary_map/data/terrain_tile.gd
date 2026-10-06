class_name PlanetTerrainTile
extends Resource

@export var face: int
@export var level: int
@export var x: int
@export var y: int
@export var dataset_ids: PackedStringArray
@export var geographic_bounds: Rect2
@export var source_spacing_m: float
@export var geometric_error_m: float

func key() -> String:
	return "%d/%d/%d/%d" % [face,level,x,y]
