# Bounded sorted consumption, independent of arrival order and RPC frequency.
class_name ServerInputQueue
extends RefCounted

var last_input_tick: int = 0
var pending_count: int = 0
var repeated_ticks: int = 0
var _config: NetworkConfig
var _tick_rate: int
var _last_server_tick: int = -1
var _slots: Array[PlayerInput] = []
var _scratch: PlayerInput = PlayerInput.new()
var _last: PlayerInput = PlayerInput.new()
var _output: PlayerInput = PlayerInput.new()


func configure(config: NetworkConfig, tick_rate: int, yaw: float = 0.0) -> void:
	_config = config
	_tick_rate = tick_rate
	_slots.clear()
	for index: int in range(config.input_queue_capacity):
		_slots.append(PlayerInput.new())
	last_input_tick = 0
	pending_count = 0
	repeated_ticks = 0
	_last_server_tick = -1
	_last = PlayerInput.new()
	_last.yaw = yaw


func receive(packet: PackedByteArray, server_tick: int) -> int:
	if _config == null or packet.size() != _config.input_history_count * InputCodec.FRAME_BYTES:
		return 0
	var accepted: int = 0
	for offset: int in range(0, packet.size(), InputCodec.FRAME_BYTES):
		if InputCodec.decode_into(packet, offset, _scratch) and enqueue(_scratch, server_tick):
			accepted += 1
	return accepted


func enqueue(inp: PlayerInput, server_tick: int) -> bool:
	if _config == null or not InputCodec.valid(inp) or not _in_window(inp.tick, server_tick):
		return false
	if inp.tick <= last_input_tick:
		return false
	var free_slot: PlayerInput
	for slot: PlayerInput in _slots:
		if slot.tick == inp.tick:
			return false
		if slot.tick == 0 and free_slot == null:
			free_slot = slot
	if free_slot == null:
		return false
	InputCodec.copy_into(inp, free_slot)
	pending_count += 1
	return true


func consume(server_tick: int) -> PlayerInput:
	if _config == null or server_tick <= _last_server_tick:
		return null
	_last_server_tick = server_tick
	var earliest: PlayerInput
	for slot: PlayerInput in _slots:
		if slot.tick == 0:
			continue
		if not _in_window(slot.tick, server_tick):
			slot.tick = 0
			pending_count -= 1
		elif earliest == null or slot.tick < earliest.tick:
			earliest = slot
	if earliest != null:
		InputCodec.copy_into(earliest, _last)
		last_input_tick = earliest.tick
		earliest.tick = 0
		pending_count -= 1
		repeated_ticks = 0
	else:
		repeated_ticks += 1
	InputCodec.copy_into(_last, _output)
	_output.tick = server_tick
	if repeated_ticks > _config.input_repeat_ticks:
		_output.move = Vector2.ZERO
		_output.buttons = 0
	return _output


func _in_window(input_tick: int, server_tick: int) -> bool:
	return input_tick >= server_tick - roundi(_config.input_max_age_seconds * _tick_rate) \
		and input_tick <= server_tick + roundi(_config.input_max_future_seconds * _tick_rate)


func reset_for_spawn(tick: int, yaw: float) -> void:
	last_input_tick = maxi(last_input_tick, tick)
	for slot: PlayerInput in _slots:
		slot.tick = 0
	pending_count = 0
	repeated_ticks = _config.input_repeat_ticks + 1
	_last.move = Vector2.ZERO
	_last.buttons = 0
	_last.yaw = yaw
	_last.pitch = 0.0
