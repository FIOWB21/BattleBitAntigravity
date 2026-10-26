# Узел игрока (CharacterBody3D), связывающий LocalInputReader, StanceController, PlayerMotor и камеру.
class_name Player
extends CharacterBody3D

signal fall_damaged(amount: float)

const DEFAULT_MOVEMENT_PATH: String = "res://src/player/default_movement.tres"

@export var movement_config: MovementConfig = preload(DEFAULT_MOVEMENT_PATH)
@export var is_local_player: bool = true
@export var stance: int = PlayerStance.STAND:
	set(value):
		stance = clampi(value, PlayerStance.STAND, PlayerStance.PRONE)
		if stance_controller != null and stance_controller.current_stance != stance:
			stance_controller.set_stance_immediate(stance)

var lean: float = 0.0
var last_fall_damage: float = 0.0
var motor: PlayerMotor = PlayerMotor.new()
var input_reader: LocalInputReader = LocalInputReader.new()
var _mouse_captured: bool = false

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var camera_effects: CameraEffects = $Head/CameraEffects
@onready var stance_controller: StanceController = get_node_or_null("StanceController") as StanceController
@onready var health_component: Node = get_node_or_null("HealthComponent")


func _ready() -> void:
	if movement_config == null:
		movement_config = load(DEFAULT_MOVEMENT_PATH) as MovementConfig
	floor_max_angle = deg_to_rad(movement_config.max_slope_angle) + PlayerMotor.SLOPE_EPSILON_RAD
	if stance_controller == null:
		stance_controller = StanceController.new()
		stance_controller.name = "StanceController"
		add_child(stance_controller)
	stance_controller.setup(self, collision_shape, head, movement_config, stance)
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
	rotation.y = inp.yaw
	if stance_controller != null:
		stance_controller.step(inp, delta)
		stance = stance_controller.current_stance
		lean = stance_controller.current_lean
	motor.simulate(self, inp, movement_config, stance, delta)
	if motor.landed_this_tick:
		last_fall_damage = motor.last_fall_damage
		if last_fall_damage > 0.0:
			apply_fall_damage(last_fall_damage)
	if head != null:
		head.rotation.x = clampf(
			inp.pitch,
			-LocalInputReader.MAX_PITCH_RAD,
			LocalInputReader.MAX_PITCH_RAD
		)


func apply_fall_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	if health_component == null:
		health_component = get_node_or_null("HealthComponent")
	if health_component != null and health_component.has_method("take_damage"):
		health_component.call("take_damage", amount)
	fall_damaged.emit(amount)


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
		var body_xform: Transform3D = get_global_transform_interpolated()
		var base_origin: Vector3 = body_xform * head.position
		var look_euler: Vector3 = Vector3(
			input_reader.pitch + eff_rot.x,
			input_reader.yaw + eff_rot.y,
			head.rotation.z + eff_rot.z
		)
		var look_basis: Basis = Basis.from_euler(look_euler)
		camera.global_transform = Transform3D(look_basis, base_origin + look_basis * eff_offset)
	else:
		camera.position = eff_offset
		camera.rotation = eff_rot


func _on_settings_changed() -> void:
	apply_settings()
