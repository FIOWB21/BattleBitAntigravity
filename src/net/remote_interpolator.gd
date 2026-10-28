# Fixed, prewarmed ring. Sampling writes into caller-owned storage.
class_name RemoteInterpolator
extends RefCounted

var count: int = 0
var _slots: Array[PlayerSnapshot] = []
var _next: int = 0
var _config: SnapshotConfig
var _tick_rate: float


func configure(config: SnapshotConfig, tick_rate: int) -> void:
	_config = config
	_tick_rate = float(tick_rate)
	_slots.clear()
	for index: int in range(config.buffer_capacity):
		_slots.append(PlayerSnapshot.new())
	clear()


func clear() -> void:
	count = 0
	_next = 0


func push(s: PlayerSnapshot) -> bool:
	if _slots.is_empty() or s == null or s.tick <= 0:
		return false
	if count > 0 and s.tick <= _at(count - 1).tick:
		return false
	_slots[_next].copy_from(s)
	_next = (_next + 1) % _slots.size()
	count = mini(count + 1, _slots.size())
	return true


func sample_into(server_tick: float, out: PlayerSnapshot) -> bool:
	if count == 0 or out == null or not is_finite(server_tick):
		return false
	var target: float = server_tick - _config.interpolation_seconds * _tick_rate
	var first: PlayerSnapshot = _at(0)
	if target <= first.tick:
		out.copy_from(first)
		return true
	for index: int in range(count - 1):
		var a: PlayerSnapshot = _at(index)
		var b: PlayerSnapshot = _at(index + 1)
		if target <= b.tick:
			var weight: float = (target - a.tick) / float(b.tick - a.tick)
			out.copy_from(b if target == b.tick else a)
			out.position = a.position.lerp(b.position, weight)
			out.velocity = a.velocity.lerp(b.velocity, weight)
			out.yaw = lerp_angle(a.yaw, b.yaw, weight)
			out.pitch = lerpf(a.pitch, b.pitch, weight)
			return true
	var latest: PlayerSnapshot = _at(count - 1)
	out.copy_from(latest)
	var seconds: float = minf((target - latest.tick) / _tick_rate, _config.extrapolation_seconds)
	out.position += latest.velocity * seconds
	return true


func _at(index: int) -> PlayerSnapshot:
	return _slots[(_next - count + index + _slots.size()) % _slots.size()]
