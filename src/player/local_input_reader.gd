# Сборщик структуры PlayerInput из глобального Input на клиенте-владельце.
class_name LocalInputReader
extends RefCounted

const MAX_PITCH_DEG: float = 89.0
const MAX_PITCH_RAD: float = deg_to_rad(MAX_PITCH_DEG)
const FALLBACK_SENSITIVITY: float = 0.2
const SLOT_ACTIONS: Array[StringName] = [
	InputActions.SLOT_1, InputActions.SLOT_2, InputActions.SLOT_3,
	InputActions.SLOT_4, InputActions.SLOT_5,
]

var tick: int = 0
var yaw: float = 0.0
var pitch: float = 0.0
var aim_sensitivity_scale: float = 1.0
var _weapon_slot: int = 0
var _weapon_cycle: int = 0
var _last_weapon: bool = false
var _throw_grenade: bool = false


func apply_mouse_delta(
	relative: Vector2,
	sensitivity: float = -1.0,
	invert_y: Variant = null
) -> void:
	var sens: float = sensitivity
	if sens < 0.0:
		sens = Settings.get_sensitivity() if Settings != null else FALLBACK_SENSITIVITY
	sens *= aim_sensitivity_scale
	var inv_y: bool = (
		bool(invert_y)
		if invert_y != null
		else (Settings.get_invert_y() if Settings != null else false)
	)
	yaw -= deg_to_rad(relative.x * sens)
	var y_sign: float = 1.0 if inv_y else -1.0
	pitch = clampf(
		pitch + deg_to_rad(relative.y * sens * y_sign),
		-MAX_PITCH_RAD,
		MAX_PITCH_RAD
	)


func handle_input_event(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		apply_mouse_delta(motion.relative)
	if event.is_echo():
		return
	for index: int in range(SLOT_ACTIONS.size()):
		if event.is_action_pressed(SLOT_ACTIONS[index]):
			_weapon_slot = index + 1
	if event.is_action_pressed(InputActions.SWITCH_WEAPON_NEXT):
		_weapon_cycle += 1
	if event.is_action_pressed(InputActions.SWITCH_WEAPON_PREV):
		_weapon_cycle -= 1
	if event.is_action_pressed(InputActions.SWITCH_WEAPON_LAST):
		_last_weapon = true
	if event.is_action_pressed(InputActions.THROW_GRENADE):
		_throw_grenade = true


func read_input() -> PlayerInput:
	var inp: PlayerInput = PlayerInput.new()
	tick += 1
	inp.tick = tick
	inp.move = Input.get_vector(
		InputActions.MOVE_LEFT,
		InputActions.MOVE_RIGHT,
		InputActions.MOVE_BACK,
		InputActions.MOVE_FORWARD
	)
	pitch = clampf(pitch, -MAX_PITCH_RAD, MAX_PITCH_RAD)
	inp.yaw = yaw
	inp.pitch = pitch
	inp.buttons = _read_buttons()
	inp.weapon_slot = _weapon_slot
	inp.weapon_cycle = signi(_weapon_cycle)
	inp.last_weapon = _last_weapon
	inp.throw_grenade = _throw_grenade
	_weapon_slot = 0
	_weapon_cycle = 0
	_last_weapon = false
	_throw_grenade = false
	return inp


func _read_buttons() -> int:
	var mask: int = 0
	if Input.is_action_pressed(InputActions.JUMP):
		mask |= PlayerInput.BTN_JUMP
	if Input.is_action_pressed(InputActions.SPRINT):
		mask |= PlayerInput.BTN_SPRINT
	if Input.is_action_pressed(InputActions.CROUCH):
		mask |= PlayerInput.BTN_CROUCH
	if Input.is_action_pressed(InputActions.PRONE):
		mask |= PlayerInput.BTN_PRONE
	if Input.is_action_pressed(InputActions.FIRE):
		mask |= PlayerInput.BTN_FIRE
	if Input.is_action_pressed(InputActions.AIM):
		mask |= PlayerInput.BTN_AIM
	if Input.is_action_pressed(InputActions.RELOAD):
		mask |= PlayerInput.BTN_RELOAD
	if Input.is_action_pressed(InputActions.LEAN_LEFT):
		mask |= PlayerInput.BTN_LEAN_L
	if Input.is_action_pressed(InputActions.LEAN_RIGHT):
		mask |= PlayerInput.BTN_LEAN_R
	return mask
