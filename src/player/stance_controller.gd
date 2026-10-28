# Компонент управления стойками (STAND / CROUCH / PRONE) и наклонами (lean) игрока.
class_name StanceController
extends Node

signal stance_changed(new_stance: int)

const HEIGHT_SNAP_EPSILON: float = 0.0005
const FLOOR_SWEEP_LIFT: float = 0.02

var current_stance: int = PlayerStance.STAND
var desired_stance: int = PlayerStance.STAND
var current_capsule_height: float = 1.8
var current_head_height: float = 1.65
var current_lean: float = 0.0
var current_lean_offset: float = 0.0
var current_lean_angle: float = 0.0

var _body: CharacterBody3D = null
var _collision_shape: CollisionShape3D = null
var _capsule: CapsuleShape3D = null
var _head: Node3D = null
var _config: MovementConfig = null
var _ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _exclude_rids: Array[RID] = []


func setup(
	body: CharacterBody3D,
	collision_shape: CollisionShape3D,
	head: Node3D,
	config: MovementConfig,
	initial_stance: int = PlayerStance.STAND
) -> void:
	_body = body
	_collision_shape = collision_shape
	_head = head
	_config = config
	if _collision_shape != null and _collision_shape.shape is CapsuleShape3D:
		_capsule = (_collision_shape.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
		_collision_shape.shape = _capsule
	_exclude_rids.clear()
	if _body != null:
		_exclude_rids.append(_body.get_rid())
	_ray_query.exclude = _exclude_rids
	set_stance_immediate(initial_stance)


func set_stance_immediate(stance_value: int) -> void:
	var clamped: int = clampi(stance_value, PlayerStance.STAND, PlayerStance.PRONE)
	var prev: int = current_stance
	current_stance = clamped
	desired_stance = clamped
	if _config != null:
		current_capsule_height = _config.capsule_height_for(current_stance)
		current_head_height = _config.head_height_for(current_stance)
	_apply_capsule_and_head()
	if prev != current_stance:
		stance_changed.emit(current_stance)


func step(inp: PlayerInput, delta: float) -> void:
	var target_stance: int = _desired_stance_from_input(inp)
	update_stance(target_stance, delta)
	update_lean(inp, delta)
	_apply_capsule_and_head()


func restore_dimensions() -> void:
	_apply_capsule_and_head()


func update_stance(target_stance: int, delta: float) -> void:
	desired_stance = clampi(target_stance, PlayerStance.STAND, PlayerStance.PRONE)
	if _config == null:
		return
	if desired_stance > current_stance:
		_step_stance_down(delta)
	elif desired_stance < current_stance:
		_step_stance_up(delta)
	else:
		_settle_current_stance_heights(delta)


func can_stand_to(target_stance: int) -> bool:
	if _config == null:
		return true
	var target_height: float = _config.capsule_height_for(target_stance)
	return can_fit_height(target_height)


func can_fit_height(target_height: float) -> bool:
	if _body == null or not _body.is_inside_tree():
		return true
	var delta_h: float = target_height - current_capsule_height
	if delta_h <= 0.0:
		return true
	var lift: float = minf(FLOOR_SWEEP_LIFT, delta_h * 0.5)
	var from_xform: Transform3D = _body.global_transform.translated(Vector3(0.0, lift, 0.0))
	var motion: Vector3 = Vector3(0.0, delta_h - lift, 0.0)
	if _body.test_move(from_xform, motion):
		return false
	_ray_query.from = _body.global_position + Vector3(0.0, current_capsule_height * 0.5, 0.0)
	_ray_query.to = _body.global_position + Vector3(0.0, target_height + 0.005, 0.0)
	_ray_query.collision_mask = _body.collision_mask
	var space_state: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	var hit: Dictionary = space_state.intersect_ray(_ray_query)
	return hit.is_empty()


func update_lean(inp: PlayerInput, delta: float) -> void:
	if _config == null:
		return
	var raw_lean: float = 0.0
	if inp != null:
		var lean_l: bool = inp.pressed(PlayerInput.BTN_LEAN_L)
		var lean_r: bool = inp.pressed(PlayerInput.BTN_LEAN_R)
		if lean_l and not lean_r:
			raw_lean = -1.0
		elif lean_r and not lean_l:
			raw_lean = 1.0
	var target_lean: float = raw_lean
	if absf(raw_lean) > 0.001:
		target_lean = raw_lean * _compute_allowed_lean_ratio(signf(raw_lean))
	current_lean = move_toward(current_lean, target_lean, _config.lean_speed * delta)
	if absf(current_lean) > 0.001:
		var limit: float = _compute_allowed_lean_ratio(signf(current_lean))
		current_lean = clampf(current_lean, -limit, limit)
	current_lean_offset = current_lean * _config.lean_offset
	current_lean_angle = -current_lean * deg_to_rad(_config.lean_angle_deg)


func _desired_stance_from_input(inp: PlayerInput) -> int:
	if inp == null:
		return desired_stance
	if inp.pressed(PlayerInput.BTN_PRONE):
		return PlayerStance.PRONE
	if inp.pressed(PlayerInput.BTN_CROUCH):
		return PlayerStance.CROUCH
	return PlayerStance.STAND


func _step_stance_down(delta: float) -> void:
	var step_time: float = maxf(_config.stance_step_time, 0.05)
	var current_target_h: float = _config.capsule_height_for(current_stance)
	if not is_equal_approx(current_capsule_height, current_target_h):
		_move_heights_toward(current_stance, step_time, delta)
		return
	var next_stance: int = mini(current_stance + 1, desired_stance)
	if current_stance != next_stance:
		current_stance = next_stance
		stance_changed.emit(current_stance)
	_move_heights_toward(current_stance, step_time, delta)


func _step_stance_up(delta: float) -> void:
	var next_stance: int = current_stance - 1
	if not can_stand_to(next_stance):
		_move_heights_toward(current_stance, maxf(_config.stance_step_time, 0.05), delta)
		return
	var up_step_time: float = maxf(_config.prone_to_stand_time * 0.5, 0.05)
	var reached: bool = _move_heights_toward(next_stance, up_step_time, delta)
	if reached:
		current_stance = next_stance
		stance_changed.emit(current_stance)


func _settle_current_stance_heights(delta: float) -> void:
	var target_h: float = _config.capsule_height_for(current_stance)
	if target_h > current_capsule_height and not can_fit_height(target_h):
		return
	var step_time: float = maxf(_config.stance_step_time, 0.05)
	_move_heights_toward(current_stance, step_time, delta)


func _move_heights_toward(stance_target: int, duration: float, delta: float) -> bool:
	var from_stance: int = clampi(
		stance_target + (1 if _config.capsule_height_for(stance_target) > current_capsule_height else -1),
		PlayerStance.STAND,
		PlayerStance.PRONE
	)
	var target_cap_h: float = _config.capsule_height_for(stance_target)
	var target_head_h: float = _config.head_height_for(stance_target)
	var cap_span: float = maxf(absf(target_cap_h - _config.capsule_height_for(from_stance)), 0.1)
	var head_span: float = maxf(absf(target_head_h - _config.head_height_for(from_stance)), 0.1)
	var safe_dur: float = maxf(duration, 0.001)
	current_capsule_height = move_toward(current_capsule_height, target_cap_h, (cap_span / safe_dur) * delta)
	current_head_height = move_toward(current_head_height, target_head_h, (head_span / safe_dur) * delta)
	if absf(current_capsule_height - target_cap_h) <= HEIGHT_SNAP_EPSILON:
		current_capsule_height = target_cap_h
	if absf(current_head_height - target_head_h) <= HEIGHT_SNAP_EPSILON:
		current_head_height = target_head_h
	return is_equal_approx(current_capsule_height, target_cap_h)


func _compute_allowed_lean_ratio(lean_sign: float) -> float:
	if _body == null or not _body.is_inside_tree() or _config == null or _config.lean_offset <= 0.0:
		return 1.0
	var head_center: Vector3 = _body.global_position + Vector3(0.0, current_head_height, 0.0)
	var right_dir: Vector3 = _body.global_transform.basis.x.normalized()
	var total_dist: float = _config.lean_offset + _config.lean_wall_margin
	_ray_query.from = head_center
	_ray_query.to = head_center + right_dir * signf(lean_sign) * total_dist
	_ray_query.collision_mask = _body.collision_mask
	var space_state: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	var hit: Dictionary = space_state.intersect_ray(_ray_query)
	if hit.is_empty():
		return 1.0
	var hit_pos: Vector3 = hit["position"]
	var hit_dist: float = head_center.distance_to(hit_pos)
	var safe_dist: float = maxf(0.0, hit_dist - _config.lean_wall_margin)
	return clampf(safe_dist / _config.lean_offset, 0.0, 1.0)


func _apply_capsule_and_head() -> void:
	var base_radius: float = _config.capsule_radius if _config != null else 0.35
	var target_radius: float = minf(base_radius, current_capsule_height * 0.5)
	if _capsule != null:
		if current_capsule_height >= _capsule.height:
			_capsule.height = current_capsule_height
			_capsule.radius = target_radius
		else:
			_capsule.radius = target_radius
			_capsule.height = current_capsule_height
	if _collision_shape != null:
		_collision_shape.position.y = current_capsule_height * 0.5
	if _head != null:
		_head.position.x = current_lean_offset
		_head.position.y = current_head_height
		_head.rotation.z = current_lean_angle
