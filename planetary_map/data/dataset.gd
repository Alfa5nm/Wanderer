class_name PlanetDataset
extends Resource

@export var id: String
@export var product_id: String
@export var title: String
@export var kind: String
@export var bounds: Rect2 # longitude, latitude; east/north positive dimensions
@export var source_spacing_m: float
@export var prepared_spacing_m: float
@export var vertical_datum: String
@export var projection: String
@export var accuracy_note: String = "Absolute accuracy not documented for this product"
@export var observation_dates: PackedStringArray
@export var source_url: String
@export var catalog_url: String
@export var lod_range: Vector2i = Vector2i(0,18)
var metadata: Dictionary
var heights: PackedFloat32Array
var image: Image
var texture: ImageTexture
var validity_bits: PackedByteArray
var width: int
var height: int
var loaded := false

func contains(lat: float, lon: float) -> bool:
	return bounds.has_point(Vector2(PlanetCoordinates.normalize_longitude(lon),lat))

func elevation(lat: float, lon: float) -> float:
	if not loaded or heights.is_empty() or not contains(lat,lon): return NAN
	var x := clampf((lon-bounds.position.x)/bounds.size.x*width-0.5,0,width-1)
	var y := clampf((bounds.end.y-lat)/bounds.size.y*height-0.5,0,height-1)
	var x0 := int(x)
	var y0 := int(y)
	var x1 := mini(x0+1,width-1)
	var y1 := mini(y0+1,height-1)
	var a := heights[y0*width+x0]
	var b := heights[y0*width+x1]
	var c := heights[y1*width+x0]
	var d := heights[y1*width+x1]
	if not is_finite(a) or not is_finite(b) or not is_finite(c) or not is_finite(d): return NAN
	return lerpf(lerpf(a,b,x-x0),lerpf(c,d,x-x0),y-y0)

func imagery_valid(lat: float, lon: float) -> bool:
	if image == null or not contains(lat,lon): return false
	var x := clampi(int((lon-bounds.position.x)/bounds.size.x*width),0,width-1)
	var y := clampi(int((bounds.end.y-lat)/bounds.size.y*height),0,height-1)
	var pixel := y*width+x
	if not validity_bits.is_empty(): return (validity_bits[pixel/8] & (1<<(pixel%8)))!=0
	return image.get_pixel(x,y).a > 0.5
