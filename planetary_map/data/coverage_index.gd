class_name MarsCoverageIndex
extends Resource

@export var records: Array[Dictionary] = []

func load_catalog(path: String) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Array:
		records.clear()
		for item in parsed:
			if item is Dictionary: records.append(item)

func intersecting(bounds: Rect2, kind: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in records:
		var bbox: Array = record.get("bbox",[])
		if bbox.size()!=4: continue
		var record_bounds:=Rect2(bbox[0],bbox[1],bbox[2]-bbox[0],bbox[3]-bbox[1])
		if record_bounds.intersects(bounds) and (kind.is_empty() or record.get("kind","")==kind): result.append(record)
	return result
