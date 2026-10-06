class_name PlanetSurveyGrid
extends MeshInstance3D

signal cell_selected(cell: Dictionary)
var service: PlanetSurfaceService
var rig: PlanetCameraRig
var enabled := false
var selected_cell: Dictionary = {}
var cells: Array[Dictionary] = []
var last_key := ""
var clock := 0.0

func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo=true
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test=false
	material_override=material
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	service.data_changed.connect(func(): last_key="")

func cell_step() -> float:
	var height := maxf((rig.distance-service.radius)*service.physical_radius_m,100)
	if height>100000: return 1.0
	if height>20000: return 0.25
	if height>4000: return 0.0625
	return 0.015625

func make_cell(lat: float,lon: float) -> Dictionary:
	var step := cell_step()
	var west: float = floor((PlanetCoordinates.normalize_longitude(lon)+180)/step)*step-180
	var south: float = floor((lat+90)/step)*step-90
	return {"id":"MARS %.6f / %.6f · %.6f°" % [south,west,step],"bounds":Rect2(west,south,step,step),"step":step}

func coverage(cell: Dictionary) -> Dictionary:
	var bounds: Rect2 = cell.bounds
	var items: Array[Dictionary] = []
	var loaded: Array[String] = []
	var dates: Array[String] = ["1997-09-15","2001-06-30"]
	for data in service.datasets:
		if data.bounds.intersects(bounds):
			var valid := 0
			for y in 3:
				for x in 3:
					var point := bounds.position+bounds.size*Vector2((x+0.5)/3,(y+0.5)/3)
					if (is_finite(data.elevation(point.y,point.x)) if data.kind=="elevation" else data.imagery_valid(point.y,point.x)): valid+=1
			if valid>0:
				loaded.append("%s · %.2f m samples · %s · %s" % [data.title,data.prepared_spacing_m,"partial" if valid<9 else "9/9 checks","bundled" if data.id in ["ctx_mosaic","ctx_gale","ctx_gale_image","hirise_bradbury","hirise_bradbury_image","mola128_gale"] else "cached"])
				for date in data.observation_dates:
					if not dates.has(date): dates.append(date)
				items.append({"id":data.product_id,"source":data.title,"spacing":data.source_spacing_m,"url":data.catalog_url})
	for item in service.source_catalog:
		var b: Array = item.get("bbox",[])
		if b.size()==4 and Rect2(b[0],b[1],b[2]-b[0],b[3]-b[1]).intersects(bounds):
			items.append({"id":item.id,"source":item.collection,"spacing":item.properties.get("gsd",0),"url":"https://stac.astrogeology.usgs.gov/api/collections/"+item.collection+"/items/"+item.id})
	var missions: Array[String] = []
	var definition: PlanetDefinition = load("res://planetary_map/data/mars.tres")
	for marker in definition.markers:
		if marker.category=="mission" and bounds.has_point(Vector2(marker.longitude,marker.latitude)): missions.append(marker.title)
	dates.sort()
	return {"published":items,"loaded":loaded,"missions":missions,"date_range":dates[0]+" → "+dates[-1]}

func select_at(local_hit: Vector3) -> void:
	if not enabled or local_hit==Vector3.ZERO: return
	var ll := PlanetCoordinates.local_to_lat_lon(local_hit)
	selected_cell=make_cell(ll.x,ll.y)
	selected_cell["coverage"]=coverage(selected_cell)
	cell_selected.emit(selected_cell)
	last_key=""

func set_enabled(value: bool) -> void:
	enabled=value
	visible=value
	if not value: selected_cell.clear()
	last_key=""

func _process(dt: float) -> void:
	clock+=dt
	visible=enabled and rig.distance/service.radius<1.22
	if not visible or clock<0.4: return
	clock=0
	var cell := make_cell(rad_to_deg(rig.pitch),rad_to_deg(rig.yaw))
	var key: String = cell.id+str(selected_cell.get("id",""))
	if key==last_key: return
	last_key=key
	rebuild(cell)

func rebuild(center: Dictionary) -> void:
	var geometry := ImmediateMesh.new()
	geometry.surface_begin(Mesh.PRIMITIVE_LINES)
	cells.clear()
	var step: float = center.step
	var origin: Vector2 = center.bounds.position
	for y in range(-3,4):
		for x in range(-3,4):
			var cell := make_cell(origin.y+(y+0.5)*step,origin.x+(x+0.5)*step)
			cells.append(cell)
			var bounds: Rect2 = cell.bounds
			var high_detail := false
			var regional := false
			for data in service.datasets:
				var point := bounds.get_center()
				if (is_finite(data.elevation(point.y,point.x)) if data.kind=="elevation" else data.imagery_valid(point.y,point.x)):
					high_detail=high_detail or data.title.begins_with("HiRISE")
					regional=regional or data.title.begins_with("CTX")
			var color := Color(0.6,0.52,0.42,0.35)
			if regional: color=Color(0.8,0.66,0.44,0.55)
			if high_detail: color=Color(0.78,0.86,0.83,0.65)
			if cell.id==selected_cell.get("id",""): color=Color(1,0.78,0.46,0.95)
			for edge in 4:
				var a := bounds.position
				var b := bounds.position+Vector2(bounds.size.x,0)
				if edge==1: a=b; b=bounds.end
				if edge==2: a=bounds.end; b=bounds.position+Vector2(0,bounds.size.y)
				if edge==3: a=bounds.position+Vector2(0,bounds.size.y); b=bounds.position
				for i in 12:
					# MOLA-only is dashed, CTX dashed pairs, HiRISE solid: readable without colour.
					if not high_detail and i%(3 if regional else 2)==0: continue
					geometry.surface_set_color(color)
					var p := a.lerp(b,float(i)/12)
					geometry.surface_add_vertex(service.position_at(p.y,p.x,5))
					p=a.lerp(b,float(i+1)/12)
					geometry.surface_add_vertex(service.position_at(p.y,p.x,5))
	geometry.surface_end()
	mesh=geometry
