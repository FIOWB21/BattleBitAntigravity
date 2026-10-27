# Pure clock estimation; all timestamps belong to the client's monotonic clock.
class_name NetClock
extends RefCounted

const USEC_PER_SECOND: float = 1000000.0
const MS_PER_SECOND: float = 1000.0

var is_synchronized: bool = false
var rtt_seconds: float = 0.0
var sample_count: int = 0
var local_tick: int = 0

var _config: NetworkConfig
var _tick_rate: float = 0.0
var _anchor_tick: float = 0.0
var _anchor_usec: int = 0
var _last_sample_usec: int = -1
var _local_phase: float = 0.0


func configure(config: NetworkConfig, tick_rate: int) -> void:
	_config = config
	_tick_rate = float(maxi(tick_rate, 1))
	reset()


func reset() -> void:
	is_synchronized = false
	rtt_seconds = 0.0
	sample_count = 0
	local_tick = 0
	_anchor_tick = 0.0
	_anchor_usec = 0
	_last_sample_usec = -1
	_local_phase = 0.0


func record_pong(sent_usec: int, received_usec: int, server_tick: int) -> bool:
	if _config == null or server_tick < 0 or sent_usec < 0:
		return false
	if received_usec < sent_usec or sent_usec <= _last_sample_usec:
		return false
	if is_synchronized and received_usec < _anchor_usec:
		return false
	var sample: float = float(received_usec - sent_usec) / USEC_PER_SECOND
	if sample > _config.ping_timeout_seconds:
		return false
	var observed_tick: float = float(server_tick) + sample * _tick_rate * 0.5
	if is_synchronized:
		rtt_seconds = lerpf(rtt_seconds, sample, _config.rtt_smoothing)
		_anchor_tick = lerpf(estimated_server_tick(received_usec), observed_tick, _config.clock_smoothing)
	else:
		rtt_seconds = sample
		_anchor_tick = observed_tick
	_anchor_usec = received_usec
	_last_sample_usec = sent_usec
	if not is_synchronized:
		_local_phase = _anchor_tick + lead_ticks()
		local_tick = floori(_local_phase)
	is_synchronized = true
	sample_count += 1
	return true


func estimated_server_tick(now_usec: int) -> float:
	if not is_synchronized:
		return 0.0
	return _anchor_tick + float(maxi(now_usec - _anchor_usec, 0)) / USEC_PER_SECOND * _tick_rate


func lead_ticks() -> float:
	if _config == null:
		return 0.0
	return rtt_seconds * _tick_rate * 0.5 + float(_config.jitter_buffer_ticks)


func advance(delta: float, now_usec: int) -> int:
	if not is_synchronized or not is_finite(delta) or delta <= 0.0:
		return local_tick
	var elapsed_ticks: float = delta * _tick_rate
	_local_phase += elapsed_ticks
	var error: float = estimated_server_tick(now_usec) + lead_ticks() - _local_phase
	var correction_limit: float = elapsed_ticks * _config.tick_slew_fraction
	_local_phase += clampf(error, -correction_limit, correction_limit)
	local_tick = maxi(local_tick, floori(_local_phase))
	return local_tick
