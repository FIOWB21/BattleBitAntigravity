# Детерминированная симуляция перемещения игрока без прямого чтения Input.
class_name PlayerMotor
extends RefCounted

const SLOPE_EPSILON_RAD: float = 0.001
const STEP_CLEARANCE_MARGIN: float = 0.004
const STEP_MIN_HEIGHT: float = 0.002
const STEP_EDGE_OVER_MARGIN: float = 0.02

var stamina: float = 100.0
var coyote_timer: float = 0.0
var is_sprinting: bool = false
var last_fall_damage: float = 0.0
var landed_this_tick: bool = false

var _stamina_initialized: bool = false
var _stamina_regen_timer: float = 0.0
var _jumped_since_grounded: bool = false
var _jumped_this_tick: bool = false
var _stepped_last_tick: bool = false
var _last_floor_y: float = 0.0
var _floor_y_initialized: bool = false
var _step_collision: KinematicCollision3D = KinematicCollision3D.new()


func simulate(
	body: CharacterBody3D,
	inp: PlayerInput,
	cfg: MovementConfig,
	stance: int,
	delta: float
) -> void:
	landed_this_tick = false
	_jumped_this_tick = false
	body.floor_max_angle = deg_to_rad(cfg.max_slope_angle) + SLOPE_EPSILON_RAD
	body.rotation.y = inp.yaw
	var was_on_floor: bool = _sync_floor_and_coyote(body, cfg, delta)
	var v: Vector3 = _compute_tick_velocity(body, inp, cfg, stance, was_on_floor, delta)
	_apply_movement_and_landing(body, cfg, was_on_floor, v, delta)


func _sync_floor_and_coyote(body: CharacterBody3D, cfg: MovementConfig, delta: float) -> bool:
	var raw_on_floor: bool = body.is_on_floor()
	var was_on_floor: bool = raw_on_floor or _stepped_last_tick
	if raw_on_floor or not _floor_y_initialized:
		_last_floor_y = body.global_position.y if body.is_inside_tree() else body.position.y
		_floor_y_initialized = true
	if was_on_floor:
		coyote_timer = cfg.coyote_time
		_jumped_since_grounded = false
	else:
		coyote_timer = maxf(0.0, coyote_timer - delta)
	return was_on_floor


func _compute_tick_velocity(
	body: CharacterBody3D,
	inp: PlayerInput,
	cfg: MovementConfig,
	stance: int,
	was_on_floor: bool,
	delta: float
) -> Vector3:
	var clamped_move: Vector2 = inp.move.limit_length(1.0)
	var wants_sprint: bool = _can_sprint(inp, cfg, stance, clamped_move)
	is_sprinting = _update_stamina(cfg, wants_sprint, delta)
	var local: Vector3 = Vector3(clamped_move.x, 0.0, -clamped_move.y)
	var body_basis: Basis = (
		body.global_transform.basis if body.is_inside_tree() else body.transform.basis
	)
	var target: Vector3 = (body_basis * local) * cfg.speed_for(stance, is_sprinting)
	var v: Vector3 = body.velocity
	var accel: float = cfg.accel_ground if was_on_floor else cfg.accel_air
	v.x = move_toward(v.x, target.x, accel * delta)
	v.z = move_toward(v.z, target.z, accel * delta)
	v.y = 0.0 if was_on_floor else (v.y - cfg.gravity * delta)
	if _should_jump(inp, stance, was_on_floor):
		v.y = cfg.jump_velocity
		coyote_timer = 0.0
		_jumped_since_grounded = true
		_stepped_last_tick = false
		_jumped_this_tick = true
	return v


func _apply_movement_and_landing(
	body: CharacterBody3D,
	cfg: MovementConfig,
	was_on_floor: bool,
	v: Vector3,
	delta: float
) -> void:
	var pre_land_vy: float = v.y
	var start_xform: Transform3D = body.global_transform if body.is_inside_tree() else body.transform
	var desired_horiz: Vector3 = Vector3(v.x, 0.0, v.z)
	var stepped: bool = false
	if was_on_floor and not _jumped_this_tick and body.is_inside_tree():
		stepped = _try_step_up(body, cfg, start_xform, desired_horiz, delta)
	_stepped_last_tick = stepped
	if stepped:
		body.velocity = desired_horiz
	else:
		body.velocity = v
		body.move_and_slide()
		if body.is_on_floor():
			_last_floor_y = body.global_position.y
	var now_on_floor: bool = body.is_on_floor() or _stepped_last_tick
	if not was_on_floor and now_on_floor:
		landed_this_tick = true
		last_fall_damage = cfg.calculate_fall_damage(pre_land_vy)
		_jumped_since_grounded = false
		coyote_timer = cfg.coyote_time


func _can_sprint(
	inp: PlayerInput,
	cfg: MovementConfig,
	stance: int,
	clamped_move: Vector2
) -> bool:
	if stance != PlayerStance.STAND:
		return false
	if inp.pressed(PlayerInput.BTN_CROUCH) or inp.pressed(PlayerInput.BTN_PRONE):
		return false
	if not inp.pressed(PlayerInput.BTN_SPRINT):
		return false
	var move_len: float = clamped_move.length()
	if move_len <= 0.001:
		return false
	return (clamped_move.y / move_len) >= cfg.sprint_min_forward_dot


func _update_stamina(cfg: MovementConfig, wants_sprint: bool, delta: float) -> bool:
	if not _stamina_initialized:
		stamina = cfg.max_stamina
		_stamina_initialized = true
	if not cfg.stamina_enabled:
		stamina = cfg.max_stamina
		_stamina_regen_timer = 0.0
		return wants_sprint
	if wants_sprint:
		_stamina_regen_timer = cfg.stamina_regen_delay
		if stamina > 0.0:
			stamina = maxf(0.0, stamina - cfg.stamina_drain_rate * delta)
			return true
		return false
	if _stamina_regen_timer > 0.0:
		_stamina_regen_timer = maxf(0.0, _stamina_regen_timer - delta)
	else:
		stamina = minf(cfg.max_stamina, stamina + cfg.stamina_regen_rate * delta)
	return false


func _should_jump(inp: PlayerInput, stance: int, was_on_floor: bool) -> bool:
	if not inp.pressed(PlayerInput.BTN_JUMP) or stance != PlayerStance.STAND:
		return false
	if inp.pressed(PlayerInput.BTN_CROUCH) or inp.pressed(PlayerInput.BTN_PRONE):
		return false
	return not _jumped_since_grounded and (was_on_floor or coyote_timer > 0.0)


func _try_step_up(
	body: CharacterBody3D,
	cfg: MovementConfig,
	start_xform: Transform3D,
	horiz_vel: Vector3,
	delta: float
) -> bool:
	var horiz_motion: Vector3 = horiz_vel * delta
	var horiz_len: float = horiz_motion.length()
	if cfg.step_height <= 0.0 or horiz_len <= 0.0001:
		return false
	var horiz_dir: Vector3 = horiz_motion / horiz_len
	var min_walkable_ny: float = cos(deg_to_rad(cfg.max_slope_angle)) - SLOPE_EPSILON_RAD
	var dist_to_edge: float = _probe_step_obstacle(
		body, cfg, start_xform, horiz_dir, horiz_len, min_walkable_ny
	)
	if dist_to_edge < 0.0:
		return false
	var max_top_y: float = _last_floor_y + cfg.step_height + STEP_CLEARANCE_MARGIN
	return _execute_step_move(
		body, start_xform, horiz_motion, horiz_dir, dist_to_edge, max_top_y, min_walkable_ny
	)


func _probe_step_obstacle(
	body: CharacterBody3D,
	cfg: MovementConfig,
	start_xform: Transform3D,
	horiz_dir: Vector3,
	horiz_len: float,
	min_walkable_ny: float
) -> float:
	var probe_xform: Transform3D = start_xform
	probe_xform.origin.y += STEP_CLEARANCE_MARGIN
	var probe_vec: Vector3 = horiz_dir * maxf(horiz_len, cfg.step_probe_distance)
	if not body.test_move(probe_xform, probe_vec, _step_collision):
		return -1.0
	if _step_collision.get_normal(0).y >= min_walkable_ny:
		return -1.0
	var to_hit: Vector3 = _step_collision.get_position(0) - start_xform.origin
	to_hit.y = 0.0
	return clampf(
		to_hit.dot(horiz_dir),
		STEP_EDGE_OVER_MARGIN,
		cfg.capsule_radius + cfg.step_probe_distance
	)


func _execute_step_move(
	body: CharacterBody3D,
	start_xform: Transform3D,
	horiz_motion: Vector3,
	horiz_dir: Vector3,
	dist_to_edge: float,
	max_top_y: float,
	min_walkable_ny: float
) -> bool:
	var max_up: float = max_top_y - start_xform.origin.y
	if max_up <= STEP_MIN_HEIGHT:
		return false
	var actual_up: float = max_up
	if body.test_move(start_xform, Vector3(0.0, max_up, 0.0), _step_collision):
		actual_up = _step_collision.get_travel().y
	if actual_up <= STEP_MIN_HEIGHT:
		return false
	var up_xform: Transform3D = start_xform
	up_xform.origin.y += actual_up
	if not _verify_step_top(body, up_xform, horiz_dir, dist_to_edge, actual_up, min_walkable_ny):
		return false
	var fwd_vec: Vector3 = horiz_motion
	if body.test_move(up_xform, fwd_vec, _step_collision):
		fwd_vec = _step_collision.get_travel()
	if Vector2(fwd_vec.x, fwd_vec.z).length() <= 0.0005:
		return false
	var fwd_xform: Transform3D = up_xform
	fwd_xform.origin += fwd_vec
	if not body.test_move(fwd_xform, Vector3(0.0, -actual_up, 0.0), _step_collision):
		return false
	var landed_xform: Transform3D = fwd_xform
	landed_xform.origin += _step_collision.get_travel()
	var climb_h: float = landed_xform.origin.y - start_xform.origin.y
	if climb_h <= STEP_MIN_HEIGHT or landed_xform.origin.y > max_top_y:
		return false
	if _step_collision.get_normal(0).y >= min_walkable_ny:
		_last_floor_y = landed_xform.origin.y
	body.global_transform = landed_xform
	return true


func _verify_step_top(
	body: CharacterBody3D,
	up_xform: Transform3D,
	horiz_dir: Vector3,
	dist_to_edge: float,
	actual_up: float,
	min_walkable_ny: float
) -> bool:
	var clear_vec: Vector3 = horiz_dir * (dist_to_edge + STEP_EDGE_OVER_MARGIN)
	if body.test_move(up_xform, clear_vec, _step_collision):
		if _step_collision.get_travel().length() < dist_to_edge + 0.002:
			return false
		clear_vec = _step_collision.get_travel()
	var over_xform: Transform3D = up_xform
	over_xform.origin += clear_vec
	if not body.test_move(over_xform, Vector3(0.0, -actual_up, 0.0), _step_collision):
		return false
	return _step_collision.get_normal(0).y >= min_walkable_ny
