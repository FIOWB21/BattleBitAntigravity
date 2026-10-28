# Complete continuation state, including motor timers and in-flight transitions.
class_name PredState
extends RefCounted

const MOTOR_FLOATS: Array[StringName] = [
	&"stamina", &"coyote_timer", &"movement_multiplier", &"_stamina_regen_timer", &"_last_floor_y"]
const MOTOR_BOOLS: Array[StringName] = [
	&"is_sprinting", &"aim_held", &"_stamina_initialized", &"_jumped_since_grounded",
	&"_jumped_this_tick", &"_stepped_last_tick", &"_floor_y_initialized"]
const STANCE_FLOATS: Array[StringName] = [
	&"current_capsule_height", &"current_head_height", &"current_lean",
	&"current_lean_offset", &"current_lean_angle"]
const YAW: int = 6
const PITCH: int = 7
const FLAGS: int = 8
const DESIRED_STANCE: int = 9
const MOTOR_BITS: int = 10
const MOTOR_AT: int = 11
const MOTOR_FLOAT_COUNT: int = 5
const STANCE_FLOAT_COUNT: int = 5
const STANCE_AT: int = MOTOR_AT + MOTOR_FLOAT_COUNT
const ADS_AT: int = STANCE_AT + STANCE_FLOAT_COUNT
const VALUE_COUNT: int = ADS_AT + 2
const FLOAT_BYTES: int = 4
const WIRE_BYTES: int = VALUE_COUNT * FLOAT_BYTES

var values: PackedFloat64Array = PackedFloat64Array()


func _init() -> void:
	values.resize(VALUE_COUNT)


func position() -> Vector3:
	return Vector3(values[0], values[1], values[2])


func velocity() -> Vector3:
	return Vector3(values[3], values[4], values[5])


func capture(actor: Player) -> void:
	for axis: int in range(3):
		values[axis] = actor.global_position[axis]
		values[axis + 3] = actor.velocity[axis]
	values[YAW] = actor.rotation.y
	values[PITCH] = actor.head.rotation.x
	values[FLAGS] = actor.stance
	if actor.is_on_floor() or actor.motor.stepped_last_tick():
		values[FLAGS] = int(values[FLAGS]) | PlayerSnapshot.GROUNDED
	if actor.movement.blocked or (actor.health_component as HealthComponent).is_dead:
		values[FLAGS] = int(values[FLAGS]) | PlayerSnapshot.DEAD
	values[DESIRED_STANCE] = actor.stance_controller.desired_stance
	values[MOTOR_BITS] = 0
	for index: int in range(MOTOR_BOOLS.size()):
		if bool(actor.motor.get(MOTOR_BOOLS[index])):
			values[MOTOR_BITS] = int(values[MOTOR_BITS]) | (1 << index)
	for index: int in range(MOTOR_FLOATS.size()):
		values[MOTOR_AT + index] = float(actor.motor.get(MOTOR_FLOATS[index]))
	for index: int in range(STANCE_FLOATS.size()):
		values[STANCE_AT + index] = float(actor.stance_controller.get(STANCE_FLOATS[index]))
	values[ADS_AT] = actor.ads.fraction
	values[ADS_AT + 1] = actor.ads.target


func apply_to(actor: Player, ack_tick: int) -> void:
	actor.global_position = position()
	actor.velocity = velocity()
	actor.rotation.y = values[YAW]
	actor.head.rotation.x = values[PITCH]
	for index: int in range(MOTOR_FLOATS.size()):
		actor.motor.set(MOTOR_FLOATS[index], values[MOTOR_AT + index])
	for index: int in range(MOTOR_BOOLS.size()):
		actor.motor.set(MOTOR_BOOLS[index], (int(values[MOTOR_BITS]) & (1 << index)) != 0)
	actor.motor.restore_floor((int(values[FLAGS]) & PlayerSnapshot.GROUNDED) != 0)
	for index: int in range(STANCE_FLOATS.size()):
		actor.stance_controller.set(STANCE_FLOATS[index], values[STANCE_AT + index])
	actor.stance_controller.current_stance = int(values[FLAGS]) & PlayerSnapshot.STANCE_MASK
	actor.stance_controller.desired_stance = int(values[DESIRED_STANCE])
	actor.stance = actor.stance_controller.current_stance
	actor.stance_controller.restore_dimensions()
	actor.lean = actor.stance_controller.current_lean
	actor.ads.restore_prediction(values[ADS_AT], values[ADS_AT + 1], ack_tick)
	actor.movement.blocked = (int(values[FLAGS]) & PlayerSnapshot.DEAD) != 0


func copy_from(source: PredState) -> void:
	for index: int in range(VALUE_COUNT):
		values[index] = source.values[index]


func differs_from(other: PredState, cfg: PredictionConfig) -> bool:
	if position().distance_to(other.position()) >= cfg.position_epsilon \
			or velocity().distance_to(other.velocity()) >= cfg.velocity_epsilon:
		return true
	for index: int in range(FLAGS, VALUE_COUNT):
		if absf(values[index] - other.values[index]) > cfg.state_epsilon:
			return true
	return false


func encode_into(bytes: PackedByteArray) -> void:
	for index: int in range(VALUE_COUNT):
		bytes.encode_float(index * FLOAT_BYTES, values[index])


func decode_from(bytes: PackedByteArray) -> bool:
	if bytes.size() != WIRE_BYTES:
		return false
	for index: int in range(VALUE_COUNT):
		var value: float = bytes.decode_float(index * FLOAT_BYTES)
		if not is_finite(value):
			return false
		values[index] = value
	var flags: int = int(values[FLAGS])
	return flags >= 0 and (flags & ~PlayerSnapshot.FLAG_MASK) == 0 \
		and (flags & PlayerSnapshot.STANCE_MASK) <= PlayerStance.PRONE \
		and values[DESIRED_STANCE] >= PlayerStance.STAND \
		and values[DESIRED_STANCE] <= PlayerStance.PRONE \
		and values[STANCE_AT] > 0.0 and values[STANCE_AT + 1] > 0.0
