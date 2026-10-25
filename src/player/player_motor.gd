# Детерминированная симуляция перемещения игрока без прямого чтения Input.
class_name PlayerMotor
extends RefCounted

const SLOPE_EPSILON_RAD: float = 0.001


func simulate(
	body: CharacterBody3D,
	inp: PlayerInput,
	cfg: MovementConfig,
	stance: int,
	delta: float
) -> void:
	body.floor_max_angle = deg_to_rad(cfg.max_slope_angle) + SLOPE_EPSILON_RAD
	body.rotation.y = inp.yaw
	var clamped_move: Vector2 = inp.move.limit_length(1.0)
	var local: Vector3 = Vector3(clamped_move.x, 0.0, -clamped_move.y)
	var body_basis: Basis = (
		body.global_transform.basis if body.is_inside_tree() else body.transform.basis
	)
	var wish: Vector3 = body_basis * local
	var sprint: bool = inp.pressed(PlayerInput.BTN_SPRINT) and clamped_move.y > 0.0
	var target: Vector3 = wish * cfg.speed_for(stance, sprint)
	var v: Vector3 = body.velocity
	if body.is_on_floor():
		v.x = move_toward(v.x, target.x, cfg.accel_ground * delta)
		v.z = move_toward(v.z, target.z, cfg.accel_ground * delta)
		if inp.pressed(PlayerInput.BTN_JUMP) and stance == MovementConfig.STANCE_STAND:
			v.y = cfg.jump_velocity
	else:
		v.x = move_toward(v.x, target.x, cfg.accel_air * delta)
		v.z = move_toward(v.z, target.z, cfg.accel_air * delta)
		v.y -= cfg.gravity * delta
	body.velocity = v
	body.move_and_slide()
