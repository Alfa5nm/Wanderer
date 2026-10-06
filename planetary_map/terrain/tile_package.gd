class_name MarsTilePackage
extends RefCounted

var base := PlanetSurfaceService.ROOT+"pyramids/"
var records: Array = []

func load_index() -> void:
	if not FileAccess.file_exists(base+"index.json"): return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(base+"index.json"))
	if parsed is Dictionary and parsed.get("schema","")=="mars-geographic-pyramid-v1" and float(parsed.get("reference_radius_m",0))==PlanetSurfaceService.REFERENCE_M:
		records=parsed.get("datasets",[])

func matching(address: Dictionary, kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in records:
		var tile: Dictionary=record.get("tile",{})
		if int(tile.get("z",-1))==int(address.get("z",-2)) and int(tile.get("x",-1))==int(address.get("x",-2)) and int(tile.get("y",-1))==int(address.get("y",-2)) and record.get("kind","")==kind: result.append(record)
	return result
