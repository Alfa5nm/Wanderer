class_name MarsTrekAdapter
extends MarsDataSourceAdapter

func _init() -> void:
	provider_id="mars_trek"
	display_name="NASA Mars Trek"
	endpoint="https://trek.nasa.gov/tiles/apidoc/trekAPI.html?body=mars"
