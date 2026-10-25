# Узел игрока (CharacterBody3D), связывающий LocalInputReader, PlayerMotor и камеру.
class_name Player
extends CharacterBody3D

const DEFAULT_MOVEMENT_PATH: String = "res://src/player/default_movement.tres"

@export var movement_config: MovementConfig = preload(DEFAULT_MOVEMENT_PATH)
@export var is_local_player: bool = true
@export var stance: int = MovementConfig.STANCE_STAND

var motor: PlayerMotor = PlayerMotor.new()
var input_reader: LocalInputReader = LocalInputReader.new()
var _mouse_captured: bool = false

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var camera_effects: CameraEffects = $Head/CameraEffects


func _ready() -> void:
	if movement_config == null:
		movement_config = load(DEFAULT_MOVEMENT_PATH) as MovementConfig
	floor_max_angle = deg_to_rad(movement_config.max_slope_angle) + PlayerMotor.SLOPE_EPSILON_RAD
	input_reader.yaw = rotation.y
	if head != null:
		input_reader.pitch = clampf(
			head.rotation.x,
			-LocalInputReader.MAX_PITCH_RAD,
			LocalInputReader.MAX_PITCH_RAD
		)
	if camera != null:
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		camera.top_level = is_local_player
	if Events != null and not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)
	apply_settings()
	if is_local_player:
		capture_mouse()
		update_camera_visuals(0.0)


func _exit_tree() -> void:
	if Events != null and Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.disconnect(_on_settings_changed)


func apply_settings() -> void:
	if camera != null and Settings != null:
		camera.fov = Settings.get_fov()
	if camera_effects != null:
		camera_effects.sync_with_settings()


func capture_mouse() -> void:
	_mouse_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	_mouse_captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_mouse_captured() -> bool:
	if DisplayServer.get_name() == "headless":
		return _mouse_captured
	return _mouse_captured and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player:
		return
	handle_input_event(event)


func handle_input_event(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.PAUSE_MENU):
		release_mouse()
		return
	if not is_mouse_captured():
		return
	if event is InputEventMouseMotion:
		input_reader.handle_input_event(event)
		if head != null:
			head.rotation.x = input_reader.pitch


func _physics_process(delta: float) -> void:
	if not is_local_player:
		return
	var inp: PlayerInput = input_reader.read_input()
	step_simulation(inp, delta)
	Game.debug["player_position"] = global_position


func _process(delta: float) -> void:
	if not is_local_player:
		return
	update_camera_visuals(delta)


func step_simulation(inp: PlayerInput, delta: float) -> void:
	motor.simulate(self, inp, movement_config, stance, delta)
	if head != null:
		head.rotation.x = clampf(
			inp.pitch,
			-LocalInputReader.MAX_PITCH_RAD,
			LocalInputReader.MAX_PITCH_RAD
		)


func update_camera_visuals(delta: float) -> void:
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	var eff_offset: Vector3 = Vector3.ZERO
	var eff_rot: Vector3 = Vector3.ZERO
	if camera_effects != null:
		camera_effects.update_effects(delta, horiz_speed, is_on_floor())
		eff_offset = camera_effects.current_offset
		eff_rot = camera_effects.current_rotation
	if camera == null or head == null:
		return
	if is_inside_tree():
		var base_origin: Vector3 = get_global_transform_interpolated().origin + head.position
		var look_euler: Vector3 = Vector3(
			input_reader.pitch + eff_rot.x,
			input_reader.yaw + eff_rot.y,
			eff_rot.z
		)
		var look_basis: Basis = Basis.from_euler(look_euler)
		camera.global_transform = Transform3D(look_basis, base_origin + look_basis * eff_offset)
	else:
		camera.position = eff_offset
		camera.rotation = eff_rot


func _on_settings_changed() -> void:
	apply_settings()
