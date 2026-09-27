extends RefCounted
class_name QuadtreeNode

## Endereço estável de uma região; a árvore lógica não processa frames sozinha.
var face: int
var depth: int
var cell: Vector2i
var key: String
var children: Array[QuadtreeNode] = []
var mesh_instance: MeshInstance3D
var mesh_data: Dictionary = {}
var bounds: AABB
var error_m: float = 0.0
var priority: float = 0.0
var is_split := false
var pending := false
var alive := true
var mining_region_hits: Dictionary = {}


func _init(face_id: int = 0, level: int = 0, address: Vector2i = Vector2i.ZERO) -> void:
	face = face_id
	depth = level
	cell = address
	key = "%d/%d/%d/%d" % [face, depth, cell.x, cell.y]
