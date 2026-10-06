class_name TerrainGenerationGraph
extends Resource

@export var surface_style := TerrainSurfaceStyle.new()
@export var nodes: Array[TerrainGraphNode] = []

func node(id: String) -> TerrainGraphNode:
	for item in nodes:
		if item.id==id: return item
	return null

static func standard(seed: int = 7462) -> TerrainGenerationGraph:
	var graph = TerrainGenerationGraph.new()
	graph.surface_style.seed=seed
	var definitions = [
		["region","Region",{},{}],
		["height","Height Field",{"region":"region"},{}],
		["grid","Grid",{"region":"region"},{"chunk_m":64.0,"spacing_m":4.0}],
		["geometry","Displace",{"field":"height","grid":"grid"},{}],
		["normals","Normals",{"geometry":"geometry","field":"height"},{}],
		["collision","Collision",{"geometry":"normals","field":"height"},{}],
		["imagery","Imagery",{"region":"region"},{"pixels":512}],
		["shading","Cavity",{"field":"height"},{"pixels":128}],
		["gravel","Gravel",{"field":"height"},{"seed":seed,"count":4096}],
		["rocks","Scatter",{"field":"height"},{"seed":seed,"density":0.0005,"exclusion_m":8.0}],
		["route","Route",{"field":"height","rocks":"rocks"},{"points":[],"width_m":0.8,"origin":"none"}]
	]
	for entry in definitions:
		var item = TerrainGraphNode.new()
		item.id=entry[0]; item.operation=entry[1]; item.inputs=entry[2]; item.parameters=entry[3]
		graph.nodes.append(item)
	return graph
