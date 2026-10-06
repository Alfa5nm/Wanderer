class_name PlanetDeployment
extends Node

signal failed(message: String)
signal surface_approach
signal handoff
var rig: PlanetCameraRig
var cover: ColorRect
var active := false
var destination := ""
var destination_title := ""
var destination_label := ""
var patch_payload: Dictionary = {}
var packed: PackedScene
var elapsed := 0.0
var ready_to_blend := false
var handed_off := false
var warm_resources: Dictionary = {}
var warm_pending: Array[String] = []
var tween: Tween

func prepare(region: PlanetRegion) -> void:
	if region == null: return
	for path in region.preload_paths:
		if warm_resources.has(path) or warm_pending.has(path): continue
		if ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path) == OK:
			warm_pending.append(path)

func start(region: PlanetRegion, site: PlanetMissionSite) -> void:
	if active: return
	prepare(region)
	if region == null or site == null or not ResourceLoader.exists(region.deployment_scene):
		failed.emit("Destination unavailable. Please try again.")
		return
	destination_title=site.title
	destination_label=region.deployment_label
	destination = region.deployment_scene
	packed = null
	var error := ResourceLoader.load_threaded_request(destination, "PackedScene")
	if error != OK:
		failed.emit("Unable to prepare destination. Please try again.")
		return
	active = true
	elapsed = 0
	ready_to_blend = false
	handed_off = false
	rig.locked = true
	rig.focus_on_coordinates(region.latitude, region.longitude, 1.05, 1.5)
	tween = create_tween()
	tween.tween_interval(1.5)
	tween.tween_callback(func():
		surface_approach.emit()
		rig.focus_on_coordinates(site.latitude, site.longitude, 1.0001, 3.0))
	tween.tween_interval(3.0)
	tween.tween_callback(func(): ready_to_blend = true)

func start_patch(region: PlanetRegion,site: PlanetMissionSite,payload: Dictionary) -> void:
	if active: return
	patch_payload=payload
	start(region,site)
	if not active: patch_payload.clear()

func cancel() -> void:
	if handed_off: return
	active = false
	patch_payload.clear()
	if tween != null: tween.kill()
	rig.locked = false
	rig.cancel_focus()
	cover.color.a = 0

func _process(dt: float) -> void:
	for path in warm_pending.duplicate():
		var warm_status := ResourceLoader.load_threaded_get_status(path)
		if warm_status == ResourceLoader.THREAD_LOAD_LOADED:
			warm_resources[path] = ResourceLoader.load_threaded_get(path)
			warm_pending.erase(path)
		elif warm_status == ResourceLoader.THREAD_LOAD_FAILED or warm_status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_warning("Optional scene preload failed: " + path)
			warm_pending.erase(path)
	if not active: return
	elapsed += dt
	var status := ResourceLoader.load_threaded_get_status(destination)
	if packed == null and (status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE or elapsed > 25):
		cancel()
		failed.emit("Destination could not load. Please try again.")
		return
	if status == ResourceLoader.THREAD_LOAD_LOADED and packed == null:
		packed = ResourceLoader.load_threaded_get(destination) as PackedScene
		if packed == null:
			cancel()
			failed.emit("Destination scene is invalid.")
			return
	if ready_to_blend and packed != null and not handed_off:
		handed_off = true
		handoff.emit()
		tween = create_tween()
		cover.color = Color(0.13,0.075,0.045,0)
		tween.tween_property(cover, "color:a", 1.0, 0.45)
		tween.tween_callback(activate)

func activate() -> void:
	if "--terrain-debug" in OS.get_cmdline_user_args(): print("PATCH activate entered")
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second",120))
	var tree := get_tree()
	var previous_parent: Node
	if not patch_payload.is_empty():
		previous_parent=patch_payload.service.get_parent()
		patch_payload.service.reparent(tree.root)
		if "--terrain-debug" in OS.get_cmdline_user_args(): print("PATCH sampler transferred")
		tree.root.set_meta("terrain_patch_handoff",patch_payload)
	var error := tree.change_scene_to_packed(packed)
	if "--terrain-debug" in OS.get_cmdline_user_args(): print("PATCH scene switch ",error)
	if error != OK:
		if previous_parent!=null:
			patch_payload.service.reparent(previous_parent)
			tree.root.remove_meta("terrain_patch_handoff")
		handed_off = false
		cancel()
		failed.emit("Destination could not activate. Please try again.")
		return
	# Persistent blend survives the old scene and reveals the existing rover.
	var layer := CanvasLayer.new()
	# Keep resources alive across old-scene teardown until gameplay holds its own refs.
	layer.set_meta("preloaded_resources",warm_resources.values())
	layer.layer = 100
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = cover.color
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	tree.root.add_child(layer)
	var reveal := layer.create_tween().set_ignore_time_scale(true)
	reveal.tween_interval(0.15)
	reveal.tween_property(overlay, "color:a", 0.0, 0.65)
	reveal.tween_callback(layer.queue_free)

