class_name PlanetClimateSample
extends RefCounted
## Resultado superficial. Índices 0..1; temperatura em Celsius, altitude em metros.
var temperature_c := 0.0
var humidity := 0.0
var precipitation := 0.0
var ocean_influence := 0.0
var rain_shadow := 0.0
var windward := 0.0
var altitude_m := 0.0

func fields() -> Vector4:
	return Vector4(temperature_c, humidity, ocean_influence, precipitation)
