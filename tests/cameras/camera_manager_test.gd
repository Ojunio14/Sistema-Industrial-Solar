extends SceneTree

const EXPECTED_CAMERA_IDS: Array[StringName] = [&"FreeFly", &"RTS", &"Orbital"]
const DIRECT_ACTIONS: Dictionary = {
	"select_camera_free_fly": {"camera_id": &"FreeFly", "key": KEY_1},
	"select_camera_rts": {"camera_id": &"RTS", "key": KEY_2},
	"select_camera_orbital": {"camera_id": &"Orbital", "key": KEY_3},
}


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var packed_scene := load("res://scenes/planet_lab/planet_lab.tscn") as PackedScene
	if not _expect(packed_scene != null, "PlanetLab could not be loaded."):
		return

	var lab := packed_scene.instantiate()
	root.add_child(lab)
	await process_frame

	var manager := root.get_node_or_null("CameraManager")
	if not _expect(manager != null, "CameraManager autoload is missing."):
		return
	if not _expect(
		manager.get_registered_camera_ids() == EXPECTED_CAMERA_IDS,
		"PlanetLab must register exactly FreeFly, RTS and Orbital in that order."
	):
		return
	if not _expect(manager.get_active_camera_id() == &"FreeFly", "FreeFly must be the initial camera."):
		return
	if not _expect(manager.get_active_camera() != null, "The initial camera must be valid."):
		return
	if not _expect(_has_exactly_one_current_camera(lab), "Exactly one Camera3D must be current initially."):
		return
	if not _expect(_has_exactly_one_active_controller(lab), "Exactly one controller must be active initially."):
		return

	for expected_id in [&"RTS", &"Orbital", &"FreeFly"]:
		if not _expect(manager.switch_to_next(), "Cyclic switch failed."):
			return
		await process_frame
		if not _expect(manager.get_active_camera_id() == expected_id, "Unexpected cyclic switch result."):
			return
		if not _expect(_has_exactly_one_current_camera(lab), "Cyclic switch left an invalid current-camera count."):
			return
		if not _expect(_has_exactly_one_active_controller(lab), "Cyclic switch left an invalid active-controller count."):
			return

	for camera_id in EXPECTED_CAMERA_IDS:
		if not _expect(manager.switch_to(camera_id), "Direct camera selection failed for '%s'." % camera_id):
			return
		await process_frame
		if not _expect(manager.get_active_camera_id() == camera_id, "Manager reported the wrong active camera."):
			return
		if not _expect(manager.get_active_camera().is_current(), "Selected camera did not become current."):
			return

	if not _expect(manager.switch_to(&"FreeFly"), "Could not reset the camera before input tests."):
		return
	_send_action(manager, &"change_cam_view")
	await process_frame
	if not _expect(manager.get_active_camera_id() == &"RTS", "change_cam_view did not perform a cyclic switch."):
		return

	for action_name in DIRECT_ACTIONS:
		var action_data: Dictionary = DIRECT_ACTIONS[action_name]
		if not _expect(InputMap.has_action(action_name), "InputMap action '%s' is missing." % action_name):
			return
		var action_events := InputMap.action_get_events(action_name)
		if not _expect(action_events.size() == 1, "InputMap action '%s' must have one key." % action_name):
			return
		var key_event := action_events[0] as InputEventKey
		if not _expect(
			key_event != null and key_event.physical_keycode == action_data["key"],
			"InputMap action '%s' has the wrong physical key." % action_name
		):
			return
		_send_action(manager, action_name)
		await process_frame
		if not _expect(
			manager.get_active_camera_id() == action_data["camera_id"],
			"Input action '%s' selected the wrong camera." % action_name
		):
			return

	var stable_id: StringName = manager.get_active_camera_id()
	var stable_camera: Camera3D = manager.get_active_camera()
	if not _expect(not manager.switch_to(&"Missing"), "Invalid camera selection must fail."):
		return
	if not _expect(manager.get_active_camera_id() == stable_id, "Invalid selection changed the active ID."):
		return
	if not _expect(manager.get_active_camera() == stable_camera, "Invalid selection changed the active camera."):
		return
	if not _expect(_has_exactly_one_current_camera(lab), "Invalid selection corrupted current-camera state."):
		return

	if not _expect(
		not manager.register_camera(&"FreeFly", stable_camera, null),
		"Duplicate camera IDs must be rejected."
	):
		return
	if not _expect(manager.get_registered_camera_ids() == EXPECTED_CAMERA_IDS, "Duplicate registration changed the registry."):
		return

	for repetition in range(10):
		for camera_id in EXPECTED_CAMERA_IDS:
			if not _expect(manager.switch_to(camera_id), "Repeated switch failed at iteration %d." % repetition):
				return
			await process_frame
			if not _expect(_has_exactly_one_current_camera(lab), "Repeated switch violated current-camera invariant."):
				return
			if not _expect(_has_exactly_one_active_controller(lab), "Repeated switch activated competing controllers."):
				return

	print("CAMERA_MANAGER_TEST_OK: 3 cameras, cyclic/direct/invalid/repeated switching")
	quit(0)


func _has_exactly_one_current_camera(lab: Node) -> bool:
	var cameras: Array[Camera3D] = []
	_collect_cameras(lab, cameras)
	var current_count := 0
	for camera in cameras:
		if camera.is_current():
			current_count += 1
	return cameras.size() == 3 and current_count == 1


func _send_action(manager: Node, action_name: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	manager._unhandled_input(event)


func _collect_cameras(node: Node, result: Array[Camera3D]) -> void:
	if node is Camera3D:
		result.append(node as Camera3D)
	for child in node.get_children():
		_collect_cameras(child, result)


func _has_exactly_one_active_controller(lab: Node) -> bool:
	var controllers: Array[Node] = [
		lab.get_node("Cameras/FreeFlyCamera"),
		lab.get_node("Cameras/RTSCamera"),
		lab.get_node("Cameras/OrbitalCamera"),
	]
	var active_count := 0
	for controller in controllers:
		if controller.is_controller_active():
			active_count += 1
	return active_count == 1


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("CAMERA_MANAGER_TEST_FAILED: " + message)
	quit(1)
	return false
