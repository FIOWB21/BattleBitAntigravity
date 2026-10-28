# Shared movement simulation without weapons, damage or gameplay interactions.
class_name PlayerMovement
extends RefCounted

var actor: Player
var blocked: bool = false
var _neutral: PlayerInput = PlayerInput.new()


func step(inp: PlayerInput, delta: float) -> void:
	if blocked:
		_neutral.tick = inp.tick
		_neutral.yaw = actor.rotation.y
		_neutral.pitch = inp.pitch
		_neutral.buttons = PlayerInput.BTN_PRONE
		actor.velocity.x = 0.0
		actor.velocity.z = 0.0
		inp = _neutral
	actor.rotation.y = inp.yaw
	var controller: StanceController = actor.stance_controller
	controller.step(inp, delta)
	actor.stance = controller.current_stance
	actor.lean = controller.current_lean
	actor.hitboxes.update_for_dimensions(controller.current_capsule_height,
		controller.current_head_height, controller.current_lean_offset)
	actor.step_ads(inp, delta, not blocked)
	actor.motor.simulate(actor, inp, actor.movement_config, actor.stance, delta)
	actor.head.rotation.x = clampf(inp.pitch,
		-LocalInputReader.MAX_PITCH_RAD, LocalInputReader.MAX_PITCH_RAD)
