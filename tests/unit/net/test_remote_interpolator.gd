extends GutTest

var _buffer: RemoteInterpolator
var _out: PlayerSnapshot
var _config: SnapshotConfig


func before_each() -> void:
	_config = preload("res://src/net/default_snapshot.tres").duplicate() as SnapshotConfig
	_buffer = RemoteInterpolator.new()
	_buffer.configure(_config, 60)
	_out = PlayerSnapshot.new()


func test_empty_and_single_snapshot_startup() -> void:
	assert_false(_buffer.sample_into(100.0, _out))
	assert_true(_buffer.push(_state(100, 4.0)))
	assert_true(_buffer.sample_into(90.0, _out))
	assert_eq(_out.position.x, 4.0)
	assert_true(_buffer.sample_into(106.0, _out))
	assert_eq(_out.position.x, 4.0)


func test_six_tick_delay_gaps_and_linear_motion() -> void:
	_buffer.push(_state(100, 0.0))
	_buffer.push(_state(108, 8.0))
	assert_true(_buffer.sample_into(110.0, _out))
	assert_almost_eq(_out.position.x, 4.0, 0.00001)
	assert_true(_buffer.sample_into(114.0, _out))
	assert_almost_eq(_out.position.x, 8.0, 0.00001)
	assert_false(_buffer.sample_into(NAN, _out))


func test_wrap_both_directions_across_pi_and_pitch() -> void:
	for direction: float in [-1.0, 1.0]:
		_buffer.clear()
		var a: PlayerSnapshot = _state(100, 0.0)
		var b: PlayerSnapshot = _state(102, 0.0)
		a.yaw = direction * deg_to_rad(179.0)
		b.yaw = -direction * deg_to_rad(179.0)
		a.pitch = -1.0
		b.pitch = 1.0
		_buffer.push(a)
		_buffer.push(b)
		assert_true(_buffer.sample_into(107.0, _out))
		assert_almost_eq(absf(_out.yaw), PI, 0.00001)
		assert_almost_eq(_out.pitch, 0.0, 0.00001)


func test_extrapolate_one_hundred_ms_then_freeze_including_long_outage() -> void:
	_buffer.push(_state(100, 0.0))
	_buffer.push(_state(102, 2.0))
	assert_true(_buffer.sample_into(111.0, _out))
	assert_almost_eq(_out.position.x, 5.0, 0.00001)
	assert_true(_buffer.sample_into(114.0, _out))
	assert_almost_eq(_out.position.x, 8.0, 0.00001)
	assert_true(_buffer.sample_into(10000.0, _out))
	assert_almost_eq(_out.position.x, 8.0, 0.00001)
	assert_true(_buffer.push(_state(10002, 20.0)))
	assert_true(_buffer.sample_into(10008.0, _out))
	assert_eq(_out.position.x, 20.0)


func test_ring_is_bounded_copies_inputs_and_rejects_stale_duplicates() -> void:
	var source: PlayerSnapshot = _state(1, 1.0)
	for tick: int in range(1, 101):
		source.tick = tick
		source.position.x = float(tick)
		assert_true(_buffer.push(source))
	assert_eq(_buffer.count, 32)
	source.position.x = 999.0
	assert_false(_buffer.push(source))
	source.tick = 99
	assert_false(_buffer.push(source))
	assert_true(_buffer.sample_into(106.0, _out))
	assert_eq(_out.position.x, 100.0)
	assert_true(_buffer.sample_into(0.0, _out))
	assert_eq(_out.position.x, 69.0)
	_buffer.clear()
	assert_false(_buffer.sample_into(106.0, _out))


func test_discrete_fields_switch_at_snapshot_boundary() -> void:
	var a: PlayerSnapshot = _state(100, 0.0)
	var b: PlayerSnapshot = _state(102, 2.0)
	a.flags = PlayerStance.STAND
	a.weapon_id = 10
	b.flags = PlayerStance.PRONE | PlayerSnapshot.AIMING
	b.weapon_id = 20
	_buffer.push(a)
	_buffer.push(b)
	_buffer.sample_into(107.0, _out)
	assert_eq(_out.flags, a.flags)
	assert_eq(_out.weapon_id, 10)
	_buffer.sample_into(108.0, _out)
	assert_eq(_out.flags, b.flags)
	assert_eq(_out.weapon_id, 20)


func test_delay_uses_configured_tick_rate_and_zero_extrapolation() -> void:
	_config.extrapolation_seconds = 0.0
	_buffer.configure(_config, 120)
	_buffer.push(_state(100, 0.0))
	_buffer.push(_state(104, 4.0))
	_buffer.sample_into(114.0, _out)
	assert_almost_eq(_out.position.x, 2.0, 0.00001)
	_buffer.sample_into(1000.0, _out)
	assert_eq(_out.position.x, 4.0)


func _state(tick: int, x: float) -> PlayerSnapshot:
	var s: PlayerSnapshot = PlayerSnapshot.new()
	s.tick = tick
	s.peer_id = 42
	s.position.x = x
	s.velocity.x = 60.0
	return s
