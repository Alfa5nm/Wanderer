class_name MarsTileAddress
extends RefCounted

const REVISION := "mars-radial-3396000-v3"

## Geographic tiles, never Web Mercator: 2^(z+1) columns, 2^z rows.
static func at(lon: float, lat: float, level: int) -> Dictionary:
	level = clampi(level,0,16)
	var rows := 1<<level
	var step := 180.0/rows
	var x := posmod(int(floor((PlanetCoordinates.normalize_longitude(lon)+180.0)/step)),rows*2)
	var y := clampi(int(floor((90.0-clampf(lat,-90,90))/step)),0,rows-1)
	return tile(level,x,y)

static func tile(level: int, x: int, y: int) -> Dictionary:
	var rows := 1<<level
	x = posmod(x,rows*2)
	y = clampi(y,0,rows-1)
	var step := 180.0/rows
	return {"z":level,"x":x,"y":y,"bounds":Rect2(-180.0+x*step,90.0-(y+1)*step,step,step)}

static func cache_key(kind: String, bounds: Rect2, size: int, provider: String = "usgs_stac") -> String:
	var identity := "%s|%s|%s|%.8f|%.8f|%.8f|%.8f|%d" % [REVISION,provider,kind,bounds.position.x,bounds.position.y,bounds.end.x,bounds.end.y,size]
	return identity.sha256_text()
