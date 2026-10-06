class_name PlanetSurfaceService
extends Node

signal data_changed
const ROOT := "res://planetary_map/assets/terrain/"
const REFERENCE_M := 3396000.0
var physical_radius_m := 3389500.0
var radius := 1.0
var manifest: Dictionary
var datasets: Array[PlanetDataset] = []
var overview: PackedByteArray
var areoid: PackedByteArray
var cache: Dictionary = {}
var cache_order: Array[String] = []
var mutex := Mutex.new()
var full_resolution := true
var render_origin := Vector3.ZERO
var render_origin64: Array[float] = [0.0,0.0,0.0]
var source_catalog: Array = []
var coverage_index := MarsCoverageIndex.new()
var source_adapters: Array[MarsDataSourceAdapter] = [MarsUSGSStacAdapter.new(),MarsPDSOdeAdapter.new(),MarsTrekAdapter.new()]

func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"manifest.json"))
	if parsed is Dictionary: manifest = parsed
	else: push_error("Required numeric Mars terrain manifest missing")
	overview = FileAccess.get_file_as_bytes(ROOT+"mola_overview.bin")
	areoid = FileAccess.get_file_as_bytes(ROOT+"areoid16.bin")
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"source_catalog.json"))
	if catalog is Array:
		source_catalog = catalog
		coverage_index.records.clear()
		for item in catalog:
			if item is Dictionary: coverage_index.records.append(item)
	for metadata in manifest.get("datasets",[]):
		add_dataset(metadata, ROOT)
	for record in source_catalog: source_adapters[0].register_record(record)
	for record in manifest.get("datasets",[]):
		var provider := source_adapters[1] if str(record.get("product_id","")).begins_with("MEG") else (source_adapters[2] if str(record.get("source_url","")).contains("trek.nasa.gov") else source_adapters[0])
		provider.register_record(record)
	for quadrant in manifest.get("mola",[]):
		var record: Dictionary=quadrant.duplicate(true)
		var bounds: Array=record.bounds.duplicate()
		if float(bounds[0])>=180:
			bounds[0]=float(bounds[0])-360
			bounds[2]=float(bounds[2])-360
		record["bounds"]=bounds
		record["kind"]="elevation"
		record["product_id"]=str(record.id).to_upper()
		record["prepared_spacing_m"]=2*PI*physical_radius_m/(360*64)
		record["vertical_datum"]="MOLA radius, 3396000 m reference"
		source_adapters[1].register_record(record)

static func checksum(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()

func add_dataset(metadata: Dictionary, base: String = "") -> PlanetDataset:
	var data := PlanetDataset.new()
	data.metadata = metadata
	for property in ["id","product_id","title","kind","source_spacing_m","prepared_spacing_m","vertical_datum","projection","source_url","catalog_url"]:
		if metadata.has(property): data.set(property,metadata[property])
	if data.id.is_empty(): data.id = data.product_id+"_"+data.kind
	var bounds: Array = metadata.get("bounds",[])
	if bounds.size()!=4 or bounds[2]<=bounds[0] or bounds[3]<=bounds[1]:
		push_warning("Invalid dataset bounds: "+data.id)
		return null
	data.bounds = Rect2(bounds[0],bounds[1],bounds[2]-bounds[0],bounds[3]-bounds[1])
	data.width = int(metadata.get("width",0))
	data.height = int(metadata.get("height",0))
	data.observation_dates=PackedStringArray(metadata.get("observation_dates",[]))
	if data.width<=0 or data.height<=0: return null
	var path: String = base+str(metadata.get("path",""))
	if not FileAccess.file_exists(path): return null
	if data.kind == "elevation":
		var bytes := FileAccess.get_file_as_bytes(path).decompress(data.width*data.height*4,FileAccess.COMPRESSION_DEFLATE)
		if bytes.size()!=data.width*data.height*4: return null
		if metadata.has("sha256") and checksum(bytes)!=metadata.sha256:
			push_warning("Corrupt optional elevation: "+data.id)
			return null
		data.heights = bytes.to_float32_array()
	else:
		data.image = Image.new()
		var image_bytes := FileAccess.get_file_as_bytes(path)
		if metadata.has("sha256") and checksum(image_bytes)!=metadata.sha256:
			push_warning("Corrupt optional imagery: "+data.id)
			return null
		if data.image.load_png_from_buffer(image_bytes)!=OK: return null
		if data.image.get_width()!=data.width or data.image.get_height()!=data.height: return null
		if metadata.get("validity_mask_encoding","")=="bit-lsb":
			var mask_path := base+str(metadata.get("validity_mask_path",""))
			if FileAccess.file_exists(mask_path):
				var packed_mask := FileAccess.get_file_as_bytes(mask_path)
				if metadata.has("validity_mask_sha256") and checksum(packed_mask)!=str(metadata.validity_mask_sha256): return null
				var expected := int(ceil(float(data.width*data.height)/8))
				data.validity_bits=packed_mask.decompress(expected,FileAccess.COMPRESSION_DEFLATE)
				if data.validity_bits.size()!=expected: return null
			else: return null
		data.image.generate_mipmaps()
		data.texture = ImageTexture.create_from_image(data.image)
	data.loaded = true
	mutex.lock()
	for old in datasets.duplicate():
		if old.id==data.id: datasets.erase(old)
	datasets.append(data)
	datasets.sort_custom(func(a: PlanetDataset,b: PlanetDataset): return a.prepared_spacing_m<b.prepared_spacing_m)
	mutex.unlock()
	data_changed.emit()
	return data

func tile_bytes(index: int, x: int, y: int) -> PackedByteArray:
	var key := "%d_%d_%d" % [index,x,y]
	if cache.has(key): return cache[key]
	var height := mini(256,5760-y*256)
	var bytes := FileAccess.get_file_as_bytes(ROOT+"mola64/"+key+".z")
	if not bytes.is_empty(): bytes = bytes.decompress(256*height*2,FileAccess.COMPRESSION_DEFLATE)
	cache[key] = bytes
	cache_order.append(key)
	if cache_order.size()>96: cache.erase(cache_order.pop_front())
	return bytes

func global_pixel(x: int,y: int) -> float:
	x = posmod(x,23040)
	y = clampi(y,0,11519)
	var index := (2 if y>=5760 else 0)+(1 if x>=11520 else 0)
	var px := x%11520
	var py := y%5760
	var bytes := tile_bytes(index,px/256,py/256)
	var offset := ((py%256)*256+px%256)*2
	if offset+2>bytes.size():
		var coarse_x := clampi(int(float(x)/16),0,1439)
		var coarse_y := clampi(int(float(y)/16),0,719)
		var coarse_offset := (coarse_y*1440+coarse_x)*2
		return overview.decode_s16(coarse_offset) if coarse_offset+2<=overview.size() else 0.0
	return bytes.decode_s16(offset)

func mola_offset(lat: float,lon: float) -> float:
	var ppd := 64.0 if full_resolution else 4.0
	var x := fposmod(lon,360)*ppd-0.5
	var y := clampf((90-lat)*ppd-0.5,0,180*ppd-1)
	var x0 := int(floor(x))
	var y0 := int(floor(y))
	var samples: Array[float] = []
	for p in [Vector2i(x0,y0),Vector2i(x0+1,y0),Vector2i(x0,y0+1),Vector2i(x0+1,y0+1)]:
		if full_resolution: samples.append(global_pixel(p.x,p.y))
		else:
			var offset := (clampi(p.y,0,719)*1440+posmod(p.x,1440))*2
			samples.append(overview.decode_s16(offset) if offset+2<=overview.size() else 0)
	return lerpf(lerpf(samples[0],samples[1],x-floor(x)),lerpf(samples[2],samples[3],x-floor(x)),y-y0)

func sample(lat: float,lon: float) -> Dictionary:
	if not PlanetCoordinates.valid(lat,lon): return {"valid":false}
	lon = PlanetCoordinates.normalize_longitude(lon)
	mutex.lock()
	var offset := mola_offset(lat,lon)
	var ident := "MOLA 64 ppd"
	var spacing := 926.0
	for index in range(datasets.size()-1,-1,-1):
		var data := datasets[index]
		if data.kind != "elevation": continue
		var elevation := data.elevation(lat,lon)
		if is_finite(elevation):
			var point := Vector2(lon,lat)
			var distance := minf(minf(point.x-data.bounds.position.x,data.bounds.end.x-point.x),minf(point.y-data.bounds.position.y,data.bounds.end.y-point.y))
			var margin := maxf(data.bounds.size.x/data.width,data.bounds.size.y/data.height)*4
			var weight := smoothstep(0.0,margin,distance)
			offset=lerpf(offset,elevation,weight)
			ident = data.title
			spacing = data.prepared_spacing_m
	mutex.unlock()
	return {"valid":true,"radial_m":REFERENCE_M+offset,"offset_m":offset,"source":ident,"spacing_m":spacing}

func position_at(lat: float,lon: float,lift_m: float = 0.0) -> Vector3:
	var result := sample(lat,lon)
	if not result.valid: return Vector3.ZERO
	return PlanetCoordinates.lat_lon_to_local(lat,lon,radius*(result.radial_m+lift_m)/physical_radius_m)

func position64(lat: float,lon: float,lift_m: float = 0.0) -> Array[float]:
	var result := sample(lat,lon)
	var r: float = radius*(result.get("radial_m",physical_radius_m)+lift_m)/physical_radius_m
	var phi := deg_to_rad(lat)
	var theta := deg_to_rad(lon)
	return [cos(phi)*sin(theta)*r,sin(phi)*r,cos(phi)*cos(theta)*r]

static func relative64(point: Array[float],origin: Array[float]) -> Vector3:
	return Vector3(point[0]-origin[0],point[1]-origin[1],point[2]-origin[2])

func normal_at(lat: float,lon: float,step: float = 0.002) -> Vector3:
	var a := position64(clampf(lat-step,-89.9999,89.9999),lon)
	var b := position64(clampf(lat+step,-89.9999,89.9999),lon)
	var c := position64(lat,lon-step)
	var d := position64(lat,lon+step)
	var normal := relative64(d,c).cross(relative64(b,a)).normalized()
	var radial := PlanetCoordinates.lat_lon_to_local(lat,lon)
	if normal.dot(radial)<0: normal = -normal
	return normal if normal.length_squared()>0.1 else radial

func hit(origin: Vector3,direction: Vector3) -> Vector3:
	# Bracket the first terrain crossing inside a shell encompassing MOLA extrema.
	var outer := radius*1.015
	var entry := PlanetCoordinates.surface_hit(origin,direction,outer)
	if entry == Vector3.ZERO and origin.length()>outer: return Vector3.ZERO
	var start := maxf(0,origin.distance_to(entry)-radius*0.001) if origin.length()>outer else 0.0
	var previous := start
	var previous_sign := 1.0
	for i in range(161):
		var t := start+i*radius*0.0003
		var point := origin+direction*t
		var ll := PlanetCoordinates.local_to_lat_lon(point)
		var sign_value := point.length()-position_at(ll.x,ll.y).length()
		if sign_value <= 0 and previous_sign>0:
			var low := previous
			var high := t
			for j in 18:
				var middle := (low+high)*0.5
				var candidate := origin+direction*middle
				ll = PlanetCoordinates.local_to_lat_lon(candidate)
				if candidate.length()>position_at(ll.x,ll.y).length(): low = middle
				else: high = middle
			return origin+direction*((low+high)*0.5)
		previous = t
		previous_sign = sign_value
	return Vector3.ZERO

func occluded(camera_position: Vector3,point: Vector3) -> bool:
	var segment := point-camera_position
	# Terrain sample checks concentrate toward the destination, where relief matters.
	for i in range(1,25):
		var fraction := 1.0-pow(1.0-float(i)/25,3)
		var probe := camera_position+segment*fraction
		var ll := PlanetCoordinates.local_to_lat_lon(probe)
		if probe.length()<position_at(ll.x,ll.y,-2).length(): return true
	return false
