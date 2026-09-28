extends Node3D

const CAMERA_ID: StringName = &"Orbital"

@export var target: Node3D
@export var mouse_sensitivity: float = 0.25
@export var zoom_step: float = 2.0
@export var orbit_radius: float = 20.0
@export var minimum_orbit_distance: float = 2.0
@export var maximum_orbit_distance: float = 100.0
@export var minimum_pitch: float = -89.0
@export var maximum_pitch: float = 89.0

@onready var camera: Camera3D = $Camera

var _yaw: float = 0.0
var _pitch: float = 0.0
var _mouse_motion := Vector2.ZERO
var _controller_active: bool = false


func _ready() -> void:
	mouse_sensitivity = maxf(mouse_sensitivity, 0.00001)
	zoom_step = maxf(zoom_step, 0.01)
	minimum_orbit_distance = maxf(minimum_orbit_distance, 0.01)
	maximum_orbit_distance = maxf(maximum_orbit_distance, minimum_orbit_distance)
	minimum_pitch = clampf(minimum_pitch, -89.9, 89.9)
	maximum_pitch = clampf(maximum_pitch, minimum_pitch, 89.9)
	orbit_radius = clampf(orbit_radius, minimum_orbit_distance, maximum_orbit_distance)
	_yaw = rotation_degrees.y
	_pitch = clampf(rotation_degrees.x, minimum_pitch, maximum_pitch)
	rotation_degrees = Vector3(_pitch, _yaw, 0.0)
	CameraManager.register_camera(CAMERA_ID, camera, self)
	_update_orbit()


func _input(event: InputEvent) -> void:
	if not _controller_active or CameraManager.designation_dragging:
		return

	if event is InputEventMouseMotion:
		_mouse_motion = event.relative
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_radius = maxf(orbit_radius - zoom_step, minimum_orbit_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_radius = minf(orbit_radius + zoom_step, maximum_orbit_distance)


func _process(_delta: float) -> void:
	if not _controller_active or CameraManager.designation_dragging:
		_mouse_motion = Vector2.ZERO
		return

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT if get_tree().get_first_node_in_group("terrain_designation") else MOUSE_BUTTON_LEFT):
		_yaw -= _mouse_motion.x * mouse_sensitivity
		_pitch = clampf(
			_pitch - _mouse_motion.y * mouse_sensitivity,
			minimum_pitch,
			maximum_pitch
		)
		rotation_degrees = Vector3(_pitch, _yaw, 0.0)

	_update_orbit()
	_mouse_motion = Vector2.ZERO


func _update_orbit() -> void:
	if not is_instance_valid(target):
		return
	global_position = target.global_position + global_basis.z * orbit_radius


func on_camera_activated() -> void:
	_controller_active = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func on_camera_deactivated() -> void:
	_controller_active = false
	_mouse_motion = Vector2.ZERO


func is_controller_active() -> bool:
	return _controller_active


func _exit_tree() -> void:
	CameraManager.unregister_camera(CAMERA_ID)
