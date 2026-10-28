class_name FireHistory
extends RefCounted

const SEED_MASK: int = 0x7fffffff

var frames: Array[FireFrame] = []
var _config: NetworkConfig
var _rate: int
var expired_tick: int = 0


func configure(config: NetworkConfig, rate: int) -> void:
	_config = config
	_rate = rate
	expired_tick = 0
	frames.clear()
	var window: int = ceili((config.input_max_age_seconds + config.input_max_future_seconds) * rate) + 1
	for index: int in range(maxi(config.input_queue_capacity, window)):
		frames.append(FireFrame.new())


static func shot_seed(input_tick: int, owner: int) -> int:
	return hash(Vector3i(owner, input_tick, 0)) & SEED_MASK


func in_window(input_tick: int, server_tick: int) -> bool:
	return _config != null and input_tick > 0 \
		and input_tick >= server_tick - roundi(_config.input_max_age_seconds * _rate) \
		and input_tick <= server_tick + roundi(_config.input_max_future_seconds * _rate)


func request(input_tick: int, seed: int, owner: int, server_tick: int) -> bool:
	if not in_window(input_tick, server_tick) or seed != shot_seed(input_tick, owner):
		return false
	var frame: FireFrame = slot(input_tick)
	if frame.requested or frame.consumed:
		return false
	frame.seed = seed
	frame.requested = true
	return true


func slot(input_tick: int) -> FireFrame:
	var frame: FireFrame = frames[input_tick % frames.size()]
	if frame.tick != input_tick:
		frame.reset(input_tick)
	return frame


func take_ready(server_tick: int) -> FireFrame:
	var earliest: FireFrame
	for frame: FireFrame in frames:
		if not frame.requested or frame.consumed:
			continue
		if not in_window(frame.tick, server_tick):
			frame.consumed = true
			expired_tick = maxi(expired_tick, frame.tick)
		elif frame.recorded and (earliest == null or frame.tick < earliest.tick):
			earliest = frame
	if earliest != null:
		earliest.consumed = true
	return earliest
