extends CanvasLayer

@onready var active_camera_label: Label = $ActiveCameraLabel
var _refresh_elapsed := 0.0


func _ready() -> void:
	CameraManager.camera_changed.connect(_on_camera_changed)
	_refresh_label(CameraManager.get_active_camera_id())


func _on_camera_changed(camera_id: StringName, _camera: Camera3D) -> void:
	_refresh_label(camera_id)


func _refresh_label(camera_id: StringName) -> void:
	active_camera_label.text = "Camera: %s" % (camera_id if not camera_id.is_empty() else "None")


func _process(delta: float) -> void:
	var planet := get_parent().get_node_or_null("Planet") as PlanetRoot
	if planet == null or planet.renderer == null:
		return
	active_camera_label.visible = planet.show_overlay
	if not active_camera_label.visible:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed < 0.2:
		return
	_refresh_elapsed = 0.0
	_refresh_label(CameraManager.get_active_camera_id())
	active_camera_label.text += "\n" + planet.debug_text()
