extends Node

signal camera_changed(camera_id: StringName, camera: Camera3D)

const DEFAULT_CAMERA_ID: StringName = &"FreeFly"
const CAMERA_ACTIONS: Dictionary = {
	"select_camera_free_fly": &"FreeFly",
	"select_camera_rts": &"RTS",
	"select_camera_orbital": &"Orbital",
}

var _cameras: Dictionary = {}
var _controllers: Dictionary = {}
var _camera_order: Array[StringName] = []
var _active_camera_id: StringName = &""
var _active_camera: Camera3D = null


func register_camera(camera_id: StringName, camera: Camera3D, controller: Node = null) -> bool:
	if camera_id.is_empty():
		push_warning("CameraManager: rejected a camera with an empty ID.")
		return false
	if not is_instance_valid(camera):
		push_warning("CameraManager: rejected invalid camera '%s'." % camera_id)
		return false
	if _cameras.has(camera_id):
		push_warning("CameraManager: duplicate camera ID '%s' was rejected." % camera_id)
		return false

	_cameras[camera_id] = camera
	_controllers[camera_id] = controller
	_camera_order.append(camera_id)

	if _active_camera == null or camera_id == DEFAULT_CAMERA_ID and _active_camera_id != DEFAULT_CAMERA_ID:
		switch_to(camera_id)
	return true


func unregister_camera(camera_id: StringName) -> bool:
	if not _cameras.has(camera_id):
		return false

	var was_active := _active_camera_id == camera_id
	if was_active:
		_notify_controller(camera_id, "on_camera_deactivated")

	_cameras.erase(camera_id)
	_controllers.erase(camera_id)
	_camera_order.erase(camera_id)

	if was_active:
		_active_camera = null
		_active_camera_id = &""
		if not _camera_order.is_empty():
			switch_to(_camera_order[0])
	return true


func switch_to(camera_id: StringName) -> bool:
	if not _cameras.has(camera_id):
		push_warning("CameraManager: camera '%s' is not registered." % camera_id)
		return false

	var next_camera := _cameras[camera_id] as Camera3D
	if not is_instance_valid(next_camera):
		push_warning("CameraManager: camera '%s' is no longer valid." % camera_id)
		return false

	if camera_id == _active_camera_id and next_camera.is_current():
		return true

	if not _active_camera_id.is_empty():
		_notify_controller(_active_camera_id, "on_camera_deactivated")

	next_camera.make_current()
	_active_camera = next_camera
	_active_camera_id = camera_id
	_notify_controller(camera_id, "on_camera_activated")
	camera_changed.emit(camera_id, next_camera)
	return true


func switch_to_next() -> bool:
	if _camera_order.is_empty():
		return false

	var current_index := _camera_order.find(_active_camera_id)
	for offset in range(1, _camera_order.size() + 1):
		var candidate_index := (current_index + offset) % _camera_order.size()
		var candidate_id := _camera_order[candidate_index]
		if _cameras.has(candidate_id) and is_instance_valid(_cameras[candidate_id]):
			return switch_to(candidate_id)
	return false


func get_registered_camera_ids() -> Array[StringName]:
	return _camera_order.duplicate()


func get_active_camera_id() -> StringName:
	return _active_camera_id


func get_active_camera() -> Camera3D:
	return _active_camera if is_instance_valid(_active_camera) else null


func has_camera(camera_id: StringName) -> bool:
	return _cameras.has(camera_id) and is_instance_valid(_cameras[camera_id])


func _notify_controller(camera_id: StringName, method_name: StringName) -> void:
	var controller := _controllers.get(camera_id) as Node
	if is_instance_valid(controller) and controller.has_method(method_name):
		controller.call(method_name)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("change_cam_view"):
		if switch_to_next():
			get_viewport().set_input_as_handled()
		return

	for action_name in CAMERA_ACTIONS:
		if event.is_action_pressed(action_name):
			if switch_to(CAMERA_ACTIONS[action_name]):
				get_viewport().set_input_as_handled()
			return
