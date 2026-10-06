class_name PlanetVisualSettings
extends Resource

@export var sun_direction := Vector3(0.6247,0.4685,-0.6247).normalized()
@export var sun_color := Color("fff1df")
@export var sun_energy := 1.7
# Representative demo angular diameter, not an ephemeris for a date.
@export var solar_diameter_degrees := 0.35
@export var star_intensity := 0.35
@export var exposure := 1.0
@export var atmosphere := MarsAtmosphereProfile.new()
