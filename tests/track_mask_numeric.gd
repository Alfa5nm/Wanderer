extends SceneTree

func fixture() -> MarsWheelTracks:
	var tracks := MarsWheelTracks.new()
	tracks.bounds=Rect2(0,0,16,16)
	tracks.mask=Image.create(1024,1024,false,Image.FORMAT_RGBA8)
	tracks.mask.fill(Color(0,tracks.NEUTRAL,0,1))
	return tracks

func _initialize() -> void:
	var one := fixture()
	var split := fixture()
	var a := Vector2(4,4); var b := Vector2(4,4.32)
	one.stamp(a,b,10.0)
	var data := one.mask.get_data()
	one.stamp(a,b,10.0)
	var checks := {"repeat_idempotent":data==one.mask.get_data()}
	for segment in 4:
		split.stamp(a+Vector2(0,segment*0.08),a+Vector2(0,(segment+1)*0.08),10.0+segment*0.08)
	var minimum := 1.0; var maximum := 0.0; var matched := true
	for i in range(2,18):
		var y := int(4.0*64)+i
		var value := one.mask.get_pixel(256,y).g
		minimum=minf(minimum,value); maximum=maxf(maximum,value)
		matched=matched and absf(value-split.mask.get_pixel(256,y).g)<=1.0/255.0
	checks["longitudinal_tread_survives"]=maximum-minimum>0.025
	checks["split_segment_phase_continuity"]=matched
	var order := fixture(); var reverse_order := fixture()
	order.stamp(a,b,10); order.stamp(a+Vector2(0.22,0),b+Vector2(0.22,0),10)
	reverse_order.stamp(a+Vector2(0.22,0),b+Vector2(0.22,0),10); reverse_order.stamp(a,b,10)
	checks["crossing_order_independent"]=order.mask.get_data()==reverse_order.mask.get_data()
	FileAccess.open("res://evidence/track_mask_numeric.json",FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
	print(JSON.stringify(checks))
	one.free(); split.free(); order.free(); reverse_order.free()
	quit(1 if checks.values().has(false) else 0)
