class_name TerrainGraphNode
extends Resource

@export var id := ""
@export var operation := ""
@export var inputs: Dictionary = {}
@export var parameters: Dictionary = {}
@export var execution := "runtime_cpu"

static func ports(op: String) -> Dictionary:
	match op:
		"Region": return {"out":"region"}
		"Height Field": return {"region":"region","out":"field"}
		"Grid": return {"region":"region","out":"grid"}
		"Displace": return {"field":"field","grid":"grid","out":"geometry"}
		"Normals", "Collision": return {"geometry":"geometry","field":"field","out":"geometry"}
		"Imagery": return {"region":"region","out":"image"}
		"Cavity": return {"field":"field","out":"image"}
		"Gravel": return {"field":"field","out":"instances"}
		"Scatter": return {"field":"field","out":"instances"}
		"Route": return {"field":"field","rocks":"instances","out":"route"}
	return {}
