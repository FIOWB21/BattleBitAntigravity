# Косметическое состояние: не читает Input, не изменяет симуляцию оружия.
class_name ViewmodelMotion
extends RefCounted

const MIN_REFERENCE_SPEED: float = 0.001

var offset: ViewmodelSpring = ViewmodelSpring.new()
var angles: ViewmodelSpring = ViewmodelSpring.new()
var reload_elapsed: float = 0.0
var reload_duration: float = 0.0
var reloading: bool = false
var _phase: float = 0.0
var _look_delta: Vector2 = Vector2.ZERO


func reset() -> void:
	offset.reset()
	angles.reset()
	reload_elapsed = 0.0
	reload_duration = 0.0
	reloading = false
	_phase = 0.0
	_look_delta = Vector2.ZERO


func add_look_delta(change: Vector2) -> void:
	_look_delta += change


func kick(config: ViewmodelConfig) -> void:
	offset.velocity += config.kick_velocity
	angles.velocity += config.kick_angular_velocity


func start_reload(duration: float) -> void:
	reload_elapsed = 0.0
	reload_duration = maxf(duration, 0.0)
	reloading = reload_duration > 0.0


func stop_reload() -> void:
	reloading = false


func advance(config: ViewmodelConfig, delta: float, speed: float,
		grounded: bool, sprinting: bool) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var walking_speed: float = maxf(speed, 0.0) if grounded else 0.0
	_phase = fposmod(_phase + walking_speed * config.bob_cycles_per_meter * TAU * delta, TAU)
	var bob: float = clampf(walking_speed / maxf(config.bob_reference_speed, MIN_REFERENCE_SPEED), 0.0, 1.0)
	var target: Vector3 = Vector3(sin(_phase), cos(_phase * 2.0), 0.0) * config.bob_offset * bob
	var sway: Vector2 = (_look_delta * config.sway_scale / delta).limit_length(config.sway_max_radians)
	_look_delta = Vector2.ZERO
	var rotation_target: Vector3 = Vector3(-sway.y, -sway.x, -sway.x)
	if sprinting:
		target += config.sprint_offset
		rotation_target += config.sprint_rotation
	var reload_amount: float = _advance_reload(config, delta)
	target += config.reload_offset * reload_amount
	rotation_target += config.reload_rotation * reload_amount
	offset.advance(target, config.spring_frequency, delta)
	angles.advance(rotation_target, config.spring_frequency, delta)


func _advance_reload(config: ViewmodelConfig, delta: float) -> float:
	if not reloading:
		return 0.0
	reload_elapsed = minf(reload_elapsed + delta, reload_duration)
	var progress: float = reload_elapsed / reload_duration
	if progress >= 1.0:
		reloading = false
	return config.reload_curve.sample(progress) if config.reload_curve != null else sin(PI * progress)
