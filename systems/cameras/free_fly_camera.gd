extends Camera3D

const CAMERA_ID: StringName = &"FreeFly"

@export_group("Movement")
@export var mouse_sensitivity: float = 0.002
@export var base_speed: float = 10.0
@export var boost_multiplier: float = 5.0
@export var min_speed_scale: float = 0.1
@export var max_speed_scale: float = 100.0
@export var speed_step_multiplier: float = 1.1

@export_group("Optional Planet Alignment")
@export var align_to_planet: bool = false
@export var planet_center: Vector3 = Vector3.ZERO

var _speed_scale: float = 1.0
var _controller_active: bool = false


func _ready() -> void:
	mouse_sensitivity = maxf(mouse_sensitivity, 0.00001)
	base_speed = maxf(base_speed, 0.01)
	boost_multiplier = maxf(boost_multiplier, 1.0)
	min_speed_scale = maxf(min_speed_scale, 0.01)
	max_speed_scale = maxf(max_speed_scale, min_speed_scale)
	speed_step_multiplier = maxf(speed_step_multiplier, 1.01)
	_speed_scale = clampf(_speed_scale, min_speed_scale, max_speed_scale)
	CameraManager.register_camera(CAMERA_ID, self, self)


func _input(event: InputEvent) -> void:
	if not _controller_active:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_object_local(Vector3.UP, -event.relative.x * mouse_sensitivity)
		rotate_object_local(Vector3.RIGHT, -event.relative.y * mouse_sensitivity)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_speed_scale = minf(_speed_scale * speed_step_multiplier, max_speed_scale)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_speed_scale = maxf(_speed_scale / speed_step_multiplier, min_speed_scale)
	elif event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	if not _controller_active or Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	var velocity := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		velocity += Vector3.FORWARD
	if Input.is_key_pressed(KEY_S):
		velocity += Vector3.BACK
	if Input.is_key_pressed(KEY_A):
		velocity += Vector3.LEFT
	if Input.is_key_pressed(KEY_D):
		velocity += Vector3.RIGHT
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		velocity += Vector3.UP
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL):
		velocity += Vector3.DOWN

	var speed := base_speed * _speed_scale
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= boost_multiplier
	global_position += transform.basis * velocity.normalized() * speed * delta

	if align_to_planet:
		_align_horizon_to_planet()


func _align_horizon_to_planet() -> void:
	if global_position.distance_squared_to(planet_center) < 1.0:
		return

	var planet_up := (global_position - planet_center).normalized()
	var camera_forward := -global_basis.z.normalized()
	if absf(camera_forward.dot(planet_up)) > 0.99:
		return

	var camera_right := camera_forward.cross(planet_up).normalized()
	var camera_up := camera_right.cross(camera_forward).normalized()
	var aligned_basis := Basis(camera_right, camera_up, -camera_forward)
	if not is_zero_approx(aligned_basis.determinant()):
		global_basis = aligned_basis


func on_camera_activated() -> void:
	_controller_active = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func on_camera_deactivated() -> void:
	_controller_active = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func is_controller_active() -> bool:
	return _controller_active


func _exit_tree() -> void:
	CameraManager.unregister_camera(CAMERA_ID)
