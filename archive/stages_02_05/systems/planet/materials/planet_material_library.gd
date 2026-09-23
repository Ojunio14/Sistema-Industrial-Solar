class_name PlanetMaterialLibrary
extends RefCounted
## Stable eight-layer order. Source PNGs remain 2K; arrays are built once per run.
const ROOT := "res://assets/textures/terrain/"
const FAMILIES := ["rock_generic", "rock_sedimentary", "rock_volcanic", "soil",
	"sand", "arid_ground", "snow_ice", "gravel"]
const SIZE := 2048
enum Family { ROCK_GENERIC, ROCK_SEDIMENTARY, ROCK_VOLCANIC, SOIL,
	SAND, ARID_GROUND, SNOW_ICE, GRAVEL }

static var _shared: PlanetMaterialLibrary
var albedo: Texture2DArray
var normal: Texture2DArray
var roughness: Texture2DArray

static func path_for(family: int, role: String) -> String:
	assert(family >= 0 and family < FAMILIES.size())
	assert(role == "albedo" or role == "normal" or role == "roughness")
	var name: String = FAMILIES[family]
	return ROOT + name + "/" + name + "_" + role + ".png"

static func shared() -> PlanetMaterialLibrary:
	if _shared == null:
		var candidate := PlanetMaterialLibrary.new()
		if candidate._build():
			_shared = candidate
	return _shared

static func validate_assets() -> PackedStringArray:
	var errors := PackedStringArray()
	var directories := DirAccess.get_directories_at(ROOT)
	directories.sort()
	var expected := PackedStringArray(FAMILIES)
	expected.sort()
	if directories != expected:
		errors.append("Expected exactly the eight canonical terrain family folders; found %s" % [directories])
	for family in range(FAMILIES.size()):
		for role in ["albedo", "normal", "roughness"]:
			var path := path_for(family, role)
			if not FileAccess.file_exists(path):
				errors.append("Missing " + path)
				continue
			var imported := ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
			var image := imported.get_image() if imported != null else null
			if image == null or image.is_empty():
				errors.append("Unreadable " + path)
				continue
			if image.get_width() != SIZE or image.get_height() != SIZE:
				errors.append("Not 2048x2048: " + path)
			var sidecar := FileAccess.get_file_as_string(path + ".import")
			if sidecar.is_empty() or not sidecar.contains("mipmaps/generate=true") or not sidecar.contains("compress/mode=2"):
				errors.append("Missing VRAM compression/mipmaps import: " + path)
			if role == "normal" and (not sidecar.contains("compress/normal_map=1") or not sidecar.contains("process/normal_map_invert_y=false")):
				errors.append("Normal GL import is not configured: " + path)
			if role == "roughness" and not sidecar.contains("compress/channel_pack=1"):
				errors.append("Linear roughness channel import is not configured: " + path)
	return errors

func _build() -> bool:
	for role in ["albedo", "normal", "roughness"]:
		var layers: Array[Image] = []
		var format := Image.FORMAT_R8 if role == "roughness" else Image.FORMAT_RGB8
		for family in range(FAMILIES.size()):
			var source := ResourceLoader.load(path_for(family, role), "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
			if source == null:
				push_error("Missing terrain material texture: " + path_for(family, role))
				return false
			var layer := source.get_image()
			if layer == null or layer.get_width() != SIZE or layer.get_height() != SIZE:
				push_error("Incompatible terrain material texture: " + path_for(family, role))
				return false
			if layer.is_compressed() and layer.decompress() != OK:
				push_error("Cannot decompress terrain material layer: " + path_for(family, role))
				return false
			layer.convert(format)
			layer.generate_mipmaps()
			layers.append(layer)
		var target := Texture2DArray.new()
		if target.create_from_images(layers) != OK:
			push_error("Cannot create terrain material array: " + role)
			return false
		match role:
			"albedo": albedo = target
			"normal": normal = target
			"roughness": roughness = target
	return true
