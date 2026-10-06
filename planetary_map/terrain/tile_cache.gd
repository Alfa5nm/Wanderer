class_name MarsTileCache
extends RefCounted

## Treat descriptor, rasters and masks as one cache entry. Bundled data never expires.
var root_path := "user://planetary_tiles/"
var ttl_seconds := 30*24*60*60
var max_entry_bytes := 64*1024*1024

func valid(result: Dictionary, allow_stale: bool = false) -> bool:
	if not result.get("ok",false) or result.get("datasets",[]).is_empty(): return false
	if not allow_stale and result.has("cached_at") and Time.get_unix_time_from_system()-float(result.cached_at)>ttl_seconds: return false
	var total := 0
	for data in result.datasets:
		var path := str(data.get("path",""))
		if not FileAccess.file_exists(path): return false
		var width := int(data.get("width",0))
		var height := int(data.get("height",0))
		if width<=0 or height<=0 or width>4096 or height>4096: return false
		var file := FileAccess.open(path,FileAccess.READ)
		if file==null or file.get_length()>max_entry_bytes: return false
		var bytes := file.get_buffer(file.get_length())
		total+=bytes.size()
		if data.get("kind","")=="elevation":
			bytes=bytes.decompress(width*height*4,FileAccess.COMPRESSION_DEFLATE)
			if bytes.size()!=width*height*4: return false
		if bytes.is_empty() or not data.has("sha256") or PlanetSurfaceService.checksum(bytes)!=str(data.sha256): return false
		if data.has("validity_mask_path"):
			var mask_path := str(data.validity_mask_path)
			if not FileAccess.file_exists(mask_path): return false
			var packed := FileAccess.get_file_as_bytes(mask_path)
			total+=packed.size()
			if data.has("validity_mask_sha256") and PlanetSurfaceService.checksum(packed)!=str(data.validity_mask_sha256): return false
			if data.get("validity_mask_encoding","")=="bit-lsb" and packed.decompress(int(ceil(float(width*height)/8)),FileAccess.COMPRESSION_DEFLATE).size()!=int(ceil(float(width*height)/8)): return false
	return total<=max_entry_bytes

func owns(path: String) -> bool:
	var base := ProjectSettings.globalize_path(root_path).simplify_path().replace("\\","/").trim_suffix("/")+"/"
	var resolved := ProjectSettings.globalize_path(path).simplify_path().replace("\\","/")
	return resolved.begins_with(base)

func members(descriptor: String, result: Dictionary) -> Array[String]:
	var paths: Array[String] = [descriptor]
	for data in result.get("datasets",[]):
		for field in ["path","validity_mask_path"]:
			var path := str(data.get(field,""))
			if owns(path) and not paths.has(path): paths.append(path)
	return paths

func discard(descriptor: String) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(descriptor)) if FileAccess.file_exists(descriptor) else null
	var paths := members(descriptor,parsed if parsed is Dictionary else {})
	for path in paths:
		if owns(path): DirAccess.remove_absolute(path)

func touch(descriptor: String, result: Dictionary) -> void:
	if not result.has("cached_at"): result["cached_at"]=Time.get_unix_time_from_system()
	result["last_access"]=Time.get_unix_time_from_system()
	var temporary := descriptor+".partial"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return
	file.store_string(JSON.stringify(result))
	file.close()
	DirAccess.rename_absolute(temporary,descriptor)

func prune(limit: int, protected_paths: Array[String] = []) -> void:
	var entries: Array[Dictionary] = []
	var seen := {}
	var total := 0
	if FileAccess.file_exists(root_path+"areoid16.bin"):
		var datum := FileAccess.open(root_path+"areoid16.bin",FileAccess.READ)
		if datum!=null: total+=datum.get_length()
	var catalog_files := DirAccess.get_files_at(root_path+"catalog/") if DirAccess.dir_exists_absolute(root_path+"catalog/") else PackedStringArray()
	for name in catalog_files:
		var path := root_path+"catalog/"+name
		var file := FileAccess.open(path,FileAccess.READ)
		if file==null: continue
		total+=file.get_length()
		entries.append({"paths":[path],"bytes":file.get_length(),"keep":false,"time":FileAccess.get_modified_time(path)})
	for name in DirAccess.get_files_at(root_path):
		if not name.ends_with(".json") or name=="request.json": continue
		var descriptor := root_path+name
		var result = JSON.parse_string(FileAccess.get_file_as_string(descriptor))
		if not result is Dictionary: continue
		var paths := members(descriptor,result)
		var bytes := 0
		var keep := false
		for path in paths:
			seen[ProjectSettings.globalize_path(path)]=true
			keep=keep or protected_paths.has(path)
			var file := FileAccess.open(path,FileAccess.READ)
			if file!=null: bytes+=file.get_length()
		total+=bytes
		entries.append({"paths":paths,"bytes":bytes,"keep":keep,"time":result.get("last_access",FileAccess.get_modified_time(descriptor))})
	# Interrupted uploads and legacy files are also bounded, but never detach live groups.
	for name in DirAccess.get_files_at(root_path):
		if name in ["areoid16.bin","request.json"]: continue
		var path := root_path+name
		if seen.has(ProjectSettings.globalize_path(path)): continue
		var file := FileAccess.open(path,FileAccess.READ)
		if file==null: continue
		total+=file.get_length()
		entries.append({"paths":[path],"bytes":file.get_length(),"keep":protected_paths.has(path),"time":FileAccess.get_modified_time(path)})
	entries.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.time)<float(b.time))
	for entry in entries:
		if total<=limit: break
		if entry.keep: continue
		for path in entry.paths:
			if owns(path): DirAccess.remove_absolute(path)
		total-=entry.bytes
