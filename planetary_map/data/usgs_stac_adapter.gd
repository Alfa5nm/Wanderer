class_name MarsUSGSStacAdapter
extends MarsDataSourceAdapter

func _init() -> void:
	provider_id="usgs_stac"
	display_name="USGS Astrogeology STAC"
	endpoint="https://stac.astrogeology.usgs.gov/api/"
	live_discovery=true

func discovery_request() -> Dictionary:
	return {"provider":provider_id,"live":true,"endpoint":endpoint,"collections":["mro_hirise_socet_dtms","mro_ctx_controlled_usgs_dtms"],"catalog_ttl_seconds":12*60*60}
