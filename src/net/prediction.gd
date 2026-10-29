# Owner-only history; replay calls movement without authoritative gameplay actions.
class_name Prediction
extends RefCounted

var config: PredictionConfig = preload("res://src/net/default_prediction.tres")
var reconciliations: int = 0
var hard_corrections: int = 0
var history_misses: int = 0
var replayed_inputs: int = 0
var last_error: float = 0.0
var compared_snapshots: int = 0
var total_error: float = 0.0
var visual_offset: Vector3 = Vector3.ZERO
var predicted_ticks: int = 0
var _inputs: Array[PlayerInput] = []
var _states: Array[PredState] = []
var _start: int = 0
var _count: int = 0
var _last_input: int = 0
var _last_ack: int = -1
var _last_snapshot: int = -1
var _pending_ack: int = 0
var _pending: bool = false
var _server: PredState = PredState.new()
var _acknowledged: PredState = PredState.new()
var _remaining: float = 0.0
var _spawn_first_input: int = -1


func configure(cfg: PredictionConfig) -> void:
	config = cfg
	_inputs.clear()
	_states.clear()
	for index: int in range(cfg.buffer_capacity):
		_inputs.append(PlayerInput.new())
		_states.append(PredState.new())
	_start = 0
	_count = 0
	_last_input = 0
	_last_ack = -1
	_last_snapshot = -1
	_pending = false
	reconciliations = 0
	hard_corrections = 0
	history_misses = 0
	replayed_inputs = 0
	predicted_ticks = 0
	last_error = 0.0
	compared_snapshots = 0
	total_error = 0.0
	visual_offset = Vector3.ZERO
	_remaining = 0.0
	_spawn_first_input = -1


func predict(actor: Player, inp: PlayerInput, delta: float) -> bool:
	if inp.tick <= _last_input or _inputs.is_empty():
		return false
	if _spawn_first_input == 0:
		_spawn_first_input = inp.tick
	if _count == _inputs.size():
		_start = (_start + 1) % _inputs.size()
		_count -= 1
	var index: int = (_start + _count) % _inputs.size()
	InputCodec.copy_into(inp, _inputs[index])
	actor.movement.step(_inputs[index], delta)
	_states[index].capture(actor)
	_count += 1
	_last_input = inp.tick
	predicted_ticks += 1
	return true


func receive(server: PredState, ack_tick: int, snapshot_tick: int) -> bool:
	if snapshot_tick <= _last_snapshot or ack_tick < _last_ack \
			or (_last_input > 0 and ack_tick > _last_input):
		return false
	if _spawn_first_input == 0 or (_spawn_first_input > 0 and ack_tick < _spawn_first_input):
		return false
	_spawn_first_input = -1
	_server.copy_from(server)
	_pending_ack = ack_tick
	_last_snapshot = snapshot_tick
	_pending = true
	return true


func reconcile(actor: Player, delta: float) -> Vector3:
	if not _pending:
		return Vector3.ZERO
	_pending = false
	var mine: PredState = _find_state(_pending_ack)
	var history_lost: bool = mine == null and _last_input > 0 and _pending_ack > 0
	var bootstrap: bool = mine == null and _last_ack < 0 and _pending_ack == 0
	var mismatch: bool = mine == null or mine.differs_from(_server, config)
	var before: Vector3 = actor.global_position
	var before_head: Vector3 = actor.head.global_position
	last_error = before.distance_to(_server.position()) if mine == null \
		else mine.position().distance_to(_server.position())
	if mine != null and _last_input > 0:
		compared_snapshots += 1
		total_error += last_error
	if mismatch:
		if history_lost:
			history_misses += 1
			_count = 0
		_server.apply_to(actor, _pending_ack)
		replayed_inputs = 0
		_replay(actor, delta)
		actor.reset_physics_interpolation()
		if bootstrap:
			last_error = before.distance_to(actor.global_position)
		if _last_input > 0 and not bootstrap:
			reconciliations += 1
		_smooth(before_head - actor.head.global_position,
			INF if history_lost else last_error)
	_acknowledged.copy_from(_server)
	_last_ack = _pending_ack
	_trim_acknowledged()
	return before - actor.global_position if mismatch else Vector3.ZERO


func advance_visual(delta: float) -> void:
	var next: float = maxf(0.0, _remaining - maxf(delta, 0.0))
	visual_offset *= next / _remaining if _remaining > 0.0 else 0.0
	_remaining = next


func reset_for_spawn(server_tick: int) -> void:
	_start = 0
	_count = 0
	_last_input = 0
	_last_ack = -1
	_last_snapshot = server_tick
	_pending = false
	visual_offset = Vector3.ZERO
	_remaining = 0.0
	_spawn_first_input = 0


func _find_state(tick: int) -> PredState:
	if tick == _last_ack:
		return _acknowledged
	for sequence: int in range(_count):
		var index: int = (_start + sequence) % _inputs.size()
		if _inputs[index].tick == tick:
			return _states[index]
	return null


func _replay(actor: Player, delta: float) -> void:
	for sequence: int in range(_count):
		var index: int = (_start + sequence) % _inputs.size()
		if _inputs[index].tick <= _pending_ack:
			continue
		actor.movement.step(_inputs[index], delta)
		_states[index].capture(actor)
		replayed_inputs += 1


func _trim_acknowledged() -> void:
	while _count > 0 and _inputs[_start].tick <= _last_ack:
		_start = (_start + 1) % _inputs.size()
		_count -= 1


func _smooth(error: Vector3, distance: float) -> void:
	if distance > config.teleport_distance or error.length() > config.teleport_distance:
		visual_offset = Vector3.ZERO
		_remaining = 0.0
		hard_corrections += 1
	else:
		visual_offset += error
		_remaining = config.smoothing_seconds
