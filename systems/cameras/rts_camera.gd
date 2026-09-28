extends Node3D

const CAMERA_ID: StringName = &"RTS"

@export_group("Movement")
@export var pan_speed: float = 20.0
@export var rotation_speed: float = 2.0
@export var zoom_speed: float = 2.0
@export var min_zoom: float = 5.0
@export var max_zoom: float = 50.0
@export var smooth_speed: float = 10.0
@export var mouse_sensitivity: float = 0.005

@export_group("View Limits")
@export var min_pitch: float = -80.0
@export var max_pitch: float = -20.0

@export_group("Future Planet Integration")
@export var align_to_planet: bool = false
@export var planet_center: Vector3 = Vector3.ZERO

@onready var gimbal: Node3D = $GimbalElevation
@onready var camera: Camera3D = $GimbalElevation/Camera

var _target_zoom: float = 20.0
var _current_zoom: float = 20.0
var _controller_active: bool = false


func _ready() -> void:
	pan_speed = maxf(pan_speed, 0.0)
	rotation_speed = maxf(rotation_speed, 0.0)
	zoom_speed = maxf(zoom_speed, 0.01)
	min_zoom = maxf(min_zoom, 0.01)
	max_zoom = maxf(max_zoom, min_zoom)
	smooth_speed = maxf(smooth_speed, 0.01)
	mouse_sensitivity = maxf(mouse_sensitivity, 0.00001)
	min_pitch = clampf(min_pitch, -89.0, 89.0)
	max_pitch = clampf(max_pitch, min_pitch, 89.0)
	_target_zoom = clampf(_target_zoom, min_zoom, max_zoom)
	_current_zoom = _target_zoom
	gimbal.rotation_degrees.x = clampf(-45.0, min_pitch, max_pitch)
	camera.position.z = _current_zoom
	CameraManager.register_camera(CAMERA_ID, camera, self)


func _process(delta: float) -> void:
	if not _controller_active or CameraManager.designation_dragging:
		return

	_handle_keyboard_rotation(delta)
	_handle_zoom(delta)
	_apply_movement(delta)
	if align_to_planet:
		_align_to_planet()


func _unhandled_input(event: InputEvent) -> void:
	if not _controller_active or CameraManager.designation_dragging:
		return

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		rotate_object_local(Vector3.UP, -event.relative.x * mouse_sensitivity)
		gimbal.rotate_object_local(Vector3.RIGHT, -event.relative.y * mouse_sensitivity)
		gimbal.rotation_degrees.x = clampf(gimbal.rotation_degrees.x, min_pitch, max_pitch)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_target_zoom = maxf(_target_zoom - zoom_speed, min_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_target_zoom = minf(_target_zoom + zoom_speed, max_zoom)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE)


func _handle_keyboard_rotation(delta: float) -> void:
	if Input.is_key_pressed(KEY_Q):
		rotate_object_local(Vector3.UP, rotation_speed * delta)
	if Input.is_key_pressed(KEY_E):
		rotate_object_local(Vector3.UP, -rotation_speed * delta)


func _handle_zoom(delta: float) -> void:
	_current_zoom = lerpf(_current_zoom, _target_zoom, minf(smooth_speed * delta, 1.0))
	camera.position.z = _current_zoom


func _apply_movement(delta: float) -> void:
	var move_direction := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move_direction -= global_basis.z
	if Input.is_key_pressed(KEY_S):
		move_direction += global_basis.z
	if Input.is_key_pressed(KEY_A):
		move_direction -= global_basis.x
	if Input.is_key_pressed(KEY_D):
		move_direction += global_basis.x

	var dynamic_speed := pan_speed * (_current_zoom / 10.0)
	global_position += move_direction.normalized() * dynamic_speed * delta


func _align_to_planet() -> void:
	if global_position.distance_squared_to(planet_center) < 0.01:
		return

	var planet_up := (global_position - planet_center).normalized()
	var right := global_basis.x.normalized()
	var backward := right.cross(planet_up).normalized()
	if backward.is_zero_approx():
		backward = global_basis.z.cross(planet_up).normalized()
	if backward.is_zero_approx():
		return
	right = planet_up.cross(backward).normalized()
	global_basis = Basis(right, planet_up, backward)


func on_camera_activated() -> void:
	_controller_active = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func on_camera_deactivated() -> void:
	_controller_active = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func is_controller_active() -> bool:
	return _controller_active


func _exit_tree() -> void:
	CameraManager.unregister_camera(CAMERA_ID)
