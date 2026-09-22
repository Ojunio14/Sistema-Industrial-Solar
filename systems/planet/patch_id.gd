class_name PatchId
extends RefCounted

enum Quadrant {
	TOP_LEFT,
	TOP_RIGHT,
	BOTTOM_LEFT,
	BOTTOM_RIGHT,
}

# Level 24 is the highest level whose adjacent UV bounds remain uniquely
# representable by the project's current float32 Vector2/Rect2 contract.
const MAX_LEVEL := 24

var face: int
var level: int
var x: int
var y: int


func _init(p_face: int = -1, p_level: int = -1, p_x: int = -1, p_y: int = -1) -> void:
	face = p_face
	level = p_level
	x = p_x
	y = p_y


static func root(p_face: int) -> PatchId:
	return PatchId.new(p_face, 0, 0, 0)


func is_valid() -> bool:
	if not PlanetMath.is_valid_face(face) or level < 0 or level > MAX_LEVEL:
		return false
	var divisions := 1 << level
	return x >= 0 and x < divisions and y >= 0 and y < divisions


func get_divisions() -> int:
	return 1 << level if level >= 0 and level <= MAX_LEVEL else 0


func get_parent_id() -> PatchId:
	if not is_valid() or level == 0:
		return null
	return PatchId.new(face, level - 1, x >> 1, y >> 1)


func get_children_ids() -> Array:
	if not is_valid() or level >= MAX_LEVEL:
		return []
	var child_level := level + 1
	var child_x := x << 1
	var child_y := y << 1
	return [
		PatchId.new(face, child_level, child_x, child_y),
		PatchId.new(face, child_level, child_x + 1, child_y),
		PatchId.new(face, child_level, child_x, child_y + 1),
		PatchId.new(face, child_level, child_x + 1, child_y + 1),
	]


func get_quadrant() -> int:
	if not is_valid() or level == 0:
		return -1
	if (y & 1) == 0:
		return Quadrant.TOP_LEFT if (x & 1) == 0 else Quadrant.TOP_RIGHT
	return Quadrant.BOTTOM_LEFT if (x & 1) == 0 else Quadrant.BOTTOM_RIGHT


func get_uv_bounds() -> Rect2:
	if not is_valid():
		return Rect2()
	var divisions := float(get_divisions())
	var size := Vector2.ONE / divisions
	return Rect2(Vector2(float(x), float(y)) / divisions, size)


func local_uv_to_face_uv(local_uv: Vector2) -> Vector2:
	assert(is_valid(), "Cannot map UV for invalid %s" % self)
	assert(PlanetMath.is_valid_uv(local_uv), "Local patch UV must be in [0, 1]: %s" % local_uv)
	var bounds := get_uv_bounds()
	return bounds.position + local_uv * bounds.size


func is_equal(other: PatchId) -> bool:
	return other != null \
		and face == other.face \
		and level == other.level \
		and x == other.x \
		and y == other.y


func stable_key() -> StringName:
	return StringName("%d:%d:%d:%d" % [face, level, x, y])


func _to_string() -> String:
	return "PatchId(face=%s, level=%d, x=%d, y=%d)" % [
		PlanetMath.get_face_name(face),
		level,
		x,
		y,
	]
