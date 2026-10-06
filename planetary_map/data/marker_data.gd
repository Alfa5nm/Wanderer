class_name PlanetMarkerData
extends Resource

@export var id: String
@export var latitude: float
@export var longitude: float
@export var title: String
@export var subtitle: String
@export var mission_id: String
@export_enum("mission", "region", "site", "science") var category: String = "mission"
@export var date: String
@export_multiline var description: String
@export var icon: Texture2D
@export var external_references: PackedStringArray
@export var min_distance: float = 1.000001
@export var max_distance: float = 8.0

func is_valid() -> bool:
	return not id.is_empty() and PlanetCoordinates.valid(latitude, longitude)
