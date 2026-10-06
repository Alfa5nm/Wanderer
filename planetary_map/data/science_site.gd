class_name PlanetScienceSite
extends PlanetMarkerData

@export var product_id := "MSL-M-ROVER-6-RDR-PLACES-V1.0"
@export var positioning_note := "Rover localization, not an exact sample point; absolute accuracy unspecified"
@export var coordinate_precision := "Archive coordinates reported to 9 decimal degrees"

static func curated() -> Array[PlanetScienceSite]:
	var result: Array[PlanetScienceSite] = []
	var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://planetary_map/data/science_targets.json"))
	if not rows is Array: return result
	for row: Dictionary in rows:
		if not row.get("position_verified",false): continue
		var site := PlanetScienceSite.new()
		site.id=row.id; site.title=row.title; site.subtitle="CURIOSITY · SCIENCE AREA"
		site.latitude=row.latitude; site.longitude=row.longitude; site.category="science"; site.mission_id="curiosity"
		site.date=row.date; site.description=row.description+"\n"+site.positioning_note+".\n"+site.coordinate_precision+"."
		site.external_references=PackedStringArray(row.references)
		site.max_distance=1.015
		if site.is_valid(): result.append(site)
	return result
