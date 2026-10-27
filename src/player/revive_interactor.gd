# Удержание interact: серверный луч, право класса и непрерывные тики ввода.
class_name ReviveInteractor
extends Node

signal progress_changed(fraction: float)

var target: PlayerLife
var progress: float = 0.0
var _player: Player
var _query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _last_tick: int = -1
var _held_ticks: int = 0


func setup(player: Player) -> void:
	_player = player
	_query.exclude = player.get_hitscan_exclude_rids()
	_query.collision_mask = HitscanQuery.DEFAULT_COLLISION_MASK | (1 << 4) | (1 << 6)
	_query.collide_with_areas = true
	_query.collide_with_bodies = true
	(player.health_component as HealthComponent).died.connect(_on_incapacitated)


func simulate(inp: PlayerInput, delta: float) -> void:
	if not is_inside_tree() or not Game.is_server_or_offline(multiplayer) or inp.tick <= _last_tick:
		return
	var continuous: bool = _last_tick >= 0 and inp.tick == _last_tick + 1
	_last_tick = inp.tick
	if not continuous or not is_finite(delta) or delta <= 0.0:
		cancel()
	if not is_finite(delta) or delta <= 0.0 or not inp.pressed(PlayerInput.BTN_INTERACT):
		cancel()
		return
	var candidate: PlayerLife = _find_target(inp)
	if candidate == null or (is_instance_valid(candidate.reviver) and candidate.reviver != self):
		cancel()
		return
	if candidate != target:
		cancel()
		target = candidate
		target.reviver = self
	else:
		_held_ticks += 1
	var duration: int = maxi(1, ceili(target.rules.revive_time * Engine.physics_ticks_per_second))
	progress = minf(float(_held_ticks) / duration, 1.0)
	progress_changed.emit(progress)
	if _held_ticks >= duration:
		target.revive()
		cancel()


func cancel() -> void:
	if is_instance_valid(target) and target.reviver == self:
		target.reviver = null
	target = null
	_held_ticks = 0
	progress = 0.0
	progress_changed.emit(progress)


func _exit_tree() -> void:
	cancel()


func _on_incapacitated(_killer_id: int) -> void:
	cancel()


func _find_target(inp: PlayerInput) -> PlayerLife:
	if _player.life.state != PlayerLife.State.ALIVE or _player.class_data == null:
		return null
	var rules: MatchRules = _player.life.rules
	if rules == null or not rules.is_valid() or not _player.class_data.passive_perks.has(rules.revive_perk):
		return null
	var pitch: float = clampf(inp.pitch, -LocalInputReader.MAX_PITCH_RAD, LocalInputReader.MAX_PITCH_RAD)
	_query.from = _player.head.global_position
	# Диагональ от стоящего медика к лежащему телу; дистанция отдельно проверяется по игрокам.
	var reach: float = rules.revive_distance + _player.movement_config.stand_head_height
	_query.to = _query.from - Basis.from_euler(Vector3(pitch, inp.yaw, 0.0)).z * reach
	var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(_query)
	var zone: HitboxZone = hit.get("collider") as HitboxZone
	if zone == null:
		return null
	var patient: Player = zone.get_entity() as Player
	if patient == null or patient == _player or patient.life.state != PlayerLife.State.DOWNED:
		return null
	if _player.global_position.distance_to(patient.global_position) > patient.life.rules.revive_distance:
		return null
	return patient.life
