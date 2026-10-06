class_name MarsDataSourceAdapter
extends Resource

## Provider-neutral discovery contract. Adapters return published product records;
## preparation and rendering remain owned by the terrain worker/service.
@export var provider_id: String
@export var display_name: String
@export var endpoint: String
var published_records: Array[Dictionary] = []
var live_discovery := false

func register_record(record: Dictionary) -> void:
	var identity := str(record.get("id",record.get("product_id","")))
	for existing in published_records:
		if str(existing.get("id",existing.get("product_id","")))==identity: return
	published_records.append(record)

func find_intersecting(bounds: Rect2, kind: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for record in published_records:
		var bbox: Array = record.get("bbox",record.get("bounds",[]))
		if bbox.size()!=4: continue
		var footprint := Rect2(float(bbox[0]),float(bbox[1]),float(bbox[2])-float(bbox[0]),float(bbox[3])-float(bbox[1]))
		if not footprint.intersects(bounds): continue
		if record.has("kind"):
			if kind.is_empty() or record.kind==kind: found.append(record)
		else:
			var assets: Dictionary = record.get("assets",{})
			var supported := kind.is_empty() or (kind=="elevation" and (assets.has("dtm") or assets.has("geoid_adjusted_dem"))) or (kind=="imagery" and (assets.has("ortho_0") or assets.has("ortho_1") or assets.has("orthoimage")))
			if supported: found.append(record)
	return found

func discovery_request() -> Dictionary:
	return {"provider":provider_id,"live":live_discovery}
