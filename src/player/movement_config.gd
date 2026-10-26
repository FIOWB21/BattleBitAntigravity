# Ресурс конфигурации параметров движения, стоек и наклонов игрока.
class_name MovementConfig
extends Resource

const STANCE_STAND: int = PlayerStance.STAND
const STANCE_CROUCH: int = PlayerStance.CROUCH
const STANCE_PRONE: int = PlayerStance.PRONE

@export var walk_speed: float = 4.0
@export var sprint_speed: float = 6.5
@export var crouch_speed: float = 2.0
@export var prone_speed: float = 0.8
@export var accel_ground: float = 40.0
@export var accel_air: float = 10.0
@export var jump_height: float = 1.1
@export var gravity: float = 15.0
@export var max_slope_angle: float = 45.0

@export var capsule_radius: float = 0.35
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.2
@export var prone_height: float = 0.5

@export var stand_head_height: float = 1.65
@export var crouch_head_height: float = 1.05
@export var prone_head_height: float = 0.35

@export var stance_step_time: float = 0.2
@export var prone_to_stand_time: float = 0.6

@export var lean_angle_deg: float = 15.0
@export var lean_offset: float = 0.4
@export var lean_speed: float = 10.0
@export var lean_wall_margin: float = 0.25

@export var sprint_min_forward_dot: float = 0.5
@export var stamina_enabled: bool = false
@export var max_stamina: float = 100.0
@export var stamina_drain_rate: float = 20.0
@export var stamina_regen_rate: float = 15.0
@export var stamina_regen_delay: float = 1.0

@export var coyote_time: float = 0.1
@export var step_height: float = 0.35
@export var step_probe_distance: float = 0.08

@export var fall_damage_min_speed: float = 12.0
@export var fall_damage_scale: float = 10.0
@export var fall_damage_max: float = 100.0

var jump_velocity: float:
	get:
		return sqrt(2.0 * gravity * maxf(jump_height, 0.0))
	set(value):
		if gravity > 0.0:
			jump_height = (value * value) / (2.0 * gravity)


func speed_for(stance: int, sprint: bool = false) -> float:
	match stance:
		STANCE_CROUCH:
			return crouch_speed
		STANCE_PRONE:
			return prone_speed
		_:
			return sprint_speed if sprint else walk_speed


func calculate_fall_damage(vertical_velocity: float) -> float:
	var downward_speed: float = -vertical_velocity
	if downward_speed <= fall_damage_min_speed:
		return 0.0
	var raw_damage: float = (downward_speed - fall_damage_min_speed) * fall_damage_scale
	return clampf(raw_damage, 0.0, fall_damage_max)


func capsule_height_for(stance: int) -> float:
	match stance:
		STANCE_CROUCH:
			return crouch_height
		STANCE_PRONE:
			return prone_height
		_:
			return stand_height


func head_height_for(stance: int) -> float:
	match stance:
		STANCE_CROUCH:
			return crouch_head_height
		STANCE_PRONE:
			return prone_head_height
		_:
			return stand_head_height
