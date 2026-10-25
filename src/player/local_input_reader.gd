# Сборщик структуры PlayerInput из глобального Input на клиенте-владельце.
class_name LocalInputReader
extends RefCounted

var tick: int = 0
var yaw: float = 0.0
var pitch: float = 0.0


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
	inp.yaw = yaw
	inp.pitch = pitch
	inp.buttons = _read_buttons()
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
