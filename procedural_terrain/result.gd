class_name TerrainPatchResult
extends RefCounted

var region: TerrainMissionRegion
var field: TerrainHeightField
var chunks: Array = []
var image: Image
var scenery_image: Image
var cavity_image: Image
var gravel: Array = []
var rocks: Array = []
var route: Dictionary = {}
var sources: Dictionary = {}
var elevation_sources: Array = []
var image_sources: Array = []
var warnings: PackedStringArray = []
var evaluated: PackedStringArray = []
var disk_hits: PackedStringArray = []
var cache_hits: PackedStringArray = []
var hashes: Dictionary = {}
var valid := false
var build_ms := 0.0
