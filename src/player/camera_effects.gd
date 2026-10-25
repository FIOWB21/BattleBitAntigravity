# Процедурные визуальные эффекты камеры (дыхание и head bob без влияния на симуляцию).
class_name CameraEffects
extends Node3D

@export var enabled: bool = true
@export var breath_frequency_hz: float = 0.3
@export var breath_amplitude_y: float = 0.004
@export var breath_pitch_rad: float = 0.001
@export var bob_frequency_per_meter: float = 0.28
@export var bob_amplitude_x: float = 0.01
@export var bob_amplitude_y: float = 0.012
@export var bob_roll_rad: float = 0.002
@export var blend_speed: float = 10.0
@export var min_move_speed: float = 0.1
@export var reference_walk_speed: float = 4.0

var current_offset: Vector3 = Vector3.ZERO
var current_rotation: Vector3 = Vector3.ZERO

var _breath_phase: float = 0.0
var _bob_phase: float = 0.0


func _ready() -> void:
	sync_with_settings()


func sync_with_settings() -> void:
	if Settings != null:
		enabled = Settings.get_camera_effects_enabled()
	if not enabled:
		reset_effects()


func reset_effects() -> void:
	current_offset = Vector3.ZERO
	current_rotation = Vector3.ZERO
	_breath_phase = 0.0
	_bob_phase = 0.0
	position = Vector3.ZERO
	rotation = Vector3.ZERO


func update_effects(delta: float, horizontal_speed: float, on_floor: bool) -> void:
	if not enabled:
		reset_effects()
		return
	_breath_phase = fposmod(_breath_phase + delta * breath_frequency_hz * TAU, TAU)
	var target_offset: Vector3 = Vector3(0.0, sin(_breath_phase) * breath_amplitude_y, 0.0)
	var target_rot: Vector3 = Vector3(cos(_breath_phase) * breath_pitch_rad, 0.0, 0.0)

	if on_floor and horizontal_speed > min_move_speed:
		_bob_phase = fposmod(
			_bob_phase + delta * horizontal_speed * bob_frequency_per_meter * TAU,
			TAU
		)
		var speed_factor: float = clampf(
			horizontal_speed / maxf(reference_walk_speed, 0.001),
			0.0,
			1.6
		)
		target_offset.x += sin(_bob_phase) * bob_amplitude_x * speed_factor
		target_offset.y += sin(_bob_phase * 2.0) * bob_amplitude_y * speed_factor
		target_rot.z += -sin(_bob_phase) * bob_roll_rad * speed_factor

	var weight: float = clampf(delta * blend_speed, 0.0, 1.0)
	current_offset = current_offset.lerp(target_offset, weight)
	current_rotation = current_rotation.lerp(target_rot, weight)
	position = current_offset
	rotation = current_rotation
