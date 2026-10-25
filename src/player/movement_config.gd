# Ресурс конфигурации параметров движения игрока.
class_name MovementConfig
extends Resource

const STANCE_STAND: int = 0
const STANCE_CROUCH: int = 1
const STANCE_PRONE: int = 2

@export var walk_speed: float = 4.0
@export var sprint_speed: float = 6.5
@export var crouch_speed: float = 2.0
@export var prone_speed: float = 0.8
@export var accel_ground: float = 40.0
@export var accel_air: float = 10.0
@export var jump_height: float = 1.1
@export var gravity: float = 15.0
@export var max_slope_angle: float = 45.0

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
