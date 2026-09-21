extends CanvasLayer

@onready var active_camera_label: Label = $ActiveCameraLabel


func _ready() -> void:
	CameraManager.camera_changed.connect(_on_camera_changed)
	_refresh_label(CameraManager.get_active_camera_id())


func _on_camera_changed(camera_id: StringName, _camera: Camera3D) -> void:
	_refresh_label(camera_id)


func _refresh_label(camera_id: StringName) -> void:
	active_camera_label.text = "Camera: %s" % (camera_id if not camera_id.is_empty() else "None")
