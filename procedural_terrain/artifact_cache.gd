class_name TerrainArtifactCache
extends RefCounted

var root_path := "user://planetary_tiles/"
var limit_bytes := 64*1024*1024
const MAX_DECODED := 64*1024*1024

func path(key: String) -> String:
	return root_path+"patch_"+key+".bin"

func read(key: String) -> Variant:
	var file := FileAccess.open(path(key),FileAccess.READ)
	if file==null or file.get_length()<72 or file.get_length()>MAX_DECODED: return null
	if file.get_buffer(4).get_string_from_ascii()!="TP03": return null
	var count := file.get_32()
	if count<1 or count>MAX_DECODED: return null
	var digest := file.get_buffer(64).get_string_from_ascii()
	var bytes := file.get_buffer(file.get_length()-72).decompress(count,FileAccess.COMPRESSION_DEFLATE)
	if bytes.size()!=count or PlanetSurfaceService.checksum(bytes)!=digest: return null
	var entry = bytes_to_var(bytes) # Never allow object deserialization.
	if not entry is Dictionary: return null
	if entry.get("kind","")=="geometry":
		var chunks = entry.get("chunks",null)
		if not chunks is Array or chunks.is_empty() or chunks.size()>2048: return null
		for chunk in chunks:
			if not chunk is Dictionary or not chunk.get("arrays",null) is Array or chunk.arrays.size()!=Mesh.ARRAY_MAX: return null
			if not chunk.arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array or not chunk.arrays[Mesh.ARRAY_INDEX] is PackedInt32Array: return null
			if chunk.arrays[Mesh.ARRAY_VERTEX].size()>200000: return null
			for index in chunk.arrays[Mesh.ARRAY_INDEX]:
				if index<0 or index>=chunk.arrays[Mesh.ARRAY_VERTEX].size(): return null
		return chunks
	if entry.get("kind","")=="numeric":
		return entry.get("value",null) if entry.get("value",null) is Dictionary else null
	if entry.get("kind","")=="image":
		var value: Dictionary = entry.get("value",{})
		for channel in entry.get("channels",["image","scenery_image"]):
			if channel not in ["image","scenery_image"]: return null
			var encoded = value.get(channel+"_png",null)
			if not encoded is PackedByteArray: return null
			var image := Image.new()
			if image.load_png_from_buffer(encoded)!=OK or image.get_width()>1024 or image.get_height()>1024: return null
			image.generate_mipmaps()
			value[channel]=image
			value.erase(channel+"_png")
		return value
	return null

func write(key: String,value: Variant) -> void:
	var entry := {}
	if value is Array: entry={"kind":"geometry","chunks":value}
	elif value is Dictionary and value.get("image",null) is Image:
		var data: Dictionary = value.duplicate()
		var channels: Array = []
		for channel in ["image","scenery_image"]:
			if not data.get(channel,null) is Image: continue
			channels.append(channel)
			data[channel+"_png"]=data[channel].save_png_to_buffer()
			data.erase(channel)
		entry={"kind":"image","value":data,"channels":channels}
	elif value is Dictionary: entry={"kind":"numeric","value":value}
	else: return
	var bytes := var_to_bytes(entry)
	if bytes.size()>MAX_DECODED: return
	DirAccess.make_dir_recursive_absolute(root_path)
	var temporary := path(key)+".partial"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return
	file.store_buffer("TP03".to_ascii_buffer())
	file.store_32(bytes.size())
	file.store_buffer(PlanetSurfaceService.checksum(bytes).to_ascii_buffer())
	file.store_buffer(bytes.compress(FileAccess.COMPRESSION_DEFLATE))
	file.close()
	DirAccess.rename_absolute(temporary,path(key))
	prune()

func prune() -> void:
	var entries: Array = []
	var total := 0
	for name in DirAccess.get_files_at(root_path):
		if not name.begins_with("patch_") or not name.ends_with(".bin"): continue
		var file := FileAccess.open(root_path+name,FileAccess.READ)
		if file==null: continue
		total+=file.get_length()
		entries.append({"path":root_path+name,"bytes":file.get_length(),"time":FileAccess.get_modified_time(root_path+name)})
	entries.sort_custom(func(a,b): return a.time<b.time)
	for entry in entries:
		if total<=limit_bytes: break
		DirAccess.remove_absolute(entry.path)
		total-=entry.bytes
