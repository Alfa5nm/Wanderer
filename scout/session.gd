class_name ScoutSession
extends Node

signal assessment_added(record: Dictionary)
signal map_changed
signal route_changed(route: Dictionary)
var findings: Dictionary = {}
var route: Dictionary = {}

static func obtain(tree: SceneTree) -> ScoutSession:
	var node := tree.root.get_node_or_null("ScoutSession") as ScoutSession
	if node==null:
		node=ScoutSession.new(); node.name="ScoutSession"; tree.root.add_child(node)
	return node

func record(value: Dictionary) -> bool:
	var key := "%s:%.5f:%.5f" % [value.kind,value.latitude,value.longitude]
	if findings.has(key): return false
	if findings.size()>=4096: findings.erase(findings.keys()[0])
	findings[key]=value
	assessment_added.emit(value); map_changed.emit()
	return true

func set_route(value: Dictionary) -> void:
	route=value
	route_changed.emit(value); map_changed.emit()

func reset() -> void:
	findings.clear(); route.clear(); map_changed.emit()

func inspected(latitude: float,longitude: float) -> bool:
	for finding in findings.values():
		if absf(finding.latitude-latitude)<0.00004 and absf(finding.longitude-longitude)<0.00004: return true
	return false
