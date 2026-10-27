extends GutTest

const STEP: float = 1.0 / 60.0
var _clock: NetClock
var _config: NetworkConfig


func before_each() -> void:
	_config = preload("res://src/net/default_network.tres").duplicate() as NetworkConfig
	_clock = NetClock.new()
	_clock.configure(_config, 60)


func test_first_sample_seeds_rtt_server_estimate_and_input_lead() -> void:
	assert_true(_clock.record_pong(1000000, 1100000, 600))
	assert_almost_eq(_clock.rtt_seconds, 0.1, 0.000001)
	assert_almost_eq(_clock.estimated_server_tick(1100000), 603.0, 0.000001)
	assert_almost_eq(_clock.lead_ticks(), 5.0, 0.000001)
	assert_eq(_clock.local_tick, 608, "Arrival estimate plus RTT/2 and two jitter ticks")
	assert_almost_eq(_clock.estimated_server_tick(2100000), 663.0, 0.000001)
	assert_eq(_clock.sample_count, 1)


func test_rtt_uses_exponential_smoothing_and_estimate_uses_its_own_weight() -> void:
	_clock.record_pong(1000000, 1100000, 600)
	assert_true(_clock.record_pong(1500000, 1700000, 630))
	assert_almost_eq(_clock.rtt_seconds, 0.12, 0.000001)
	assert_almost_eq(_clock.estimated_server_tick(1700000), 638.4, 0.000001)
	assert_almost_eq(_clock.lead_ticks(), 5.6, 0.000001)
	assert_eq(_clock.local_tick, 608, "Subsequent samples do not jump the local clock")


func test_tick_rate_and_jitter_buffer_are_configurable() -> void:
	_config.jitter_buffer_ticks = 1
	_clock.configure(_config, 120)
	_clock.record_pong(0, 100000, 1000)
	assert_almost_eq(_clock.lead_ticks(), 7.0, 0.000001)
	assert_eq(_clock.local_tick, 1013)
	assert_eq(_clock.advance(1.0 / 120.0, 108333), 1013, "Fractional ticks round down")


func test_constant_latency_keeps_expected_lead_for_many_ticks() -> void:
	_clock.record_pong(0, 100000, 600)
	for index: int in range(1, 601):
		var now: int = 100000 + roundi(float(index) * STEP * NetClock.USEC_PER_SECOND)
		var tick: int = _clock.advance(STEP, now)
		var difference: float = float(tick) - _clock.estimated_server_tick(now)
		assert_almost_eq(difference, 5.0, 1.01)
	assert_almost_eq(_clock.rtt_seconds, 0.1, 0.000001)


func test_correction_slews_both_directions_without_reversing_tick() -> void:
	_clock.record_pong(0, 100000, 600)
	var previous: int = _clock.local_tick
	_clock.record_pong(500000, 600000, 900)
	assert_eq(_clock.local_tick, previous)
	for index: int in range(1, 301):
		var now: int = 600000 + roundi(float(index) * STEP * NetClock.USEC_PER_SECOND)
		var tick: int = _clock.advance(STEP, now)
		assert_true(tick >= previous and tick <= previous + 2)
		previous = tick
	_clock.record_pong(6000000, 6100000, 300)
	for index: int in range(1, 301):
		var now: int = 6100000 + roundi(float(index) * STEP * NetClock.USEC_PER_SECOND)
		var tick: int = _clock.advance(STEP, now)
		assert_true(tick >= previous and tick <= previous + 1)
		previous = tick


func test_latency_change_converges_without_a_tick_jump() -> void:
	_clock.record_pong(0, 100000, 600)
	var now: int = 100000
	for index: int in range(1, 1201):
		now = 100000 + roundi(float(index) * STEP * NetClock.USEC_PER_SECOND)
		if index % 30 == 0:
			var server_at_reply: int = floori(600.0 + float(now) / NetClock.USEC_PER_SECOND * 60.0 - 6.0)
			_clock.record_pong(now - 200000, now, server_at_reply)
		_clock.advance(STEP, now)
	assert_almost_eq(_clock.rtt_seconds, 0.2, 0.0001)
	assert_almost_eq(float(_clock.local_tick) - _clock.estimated_server_tick(now), 8.0, 1.0)


func test_invalid_stale_duplicate_and_timed_out_samples_do_not_change_clock() -> void:
	assert_false(_clock.record_pong(-1, 1000, 10))
	assert_false(_clock.record_pong(1000, 999, 10))
	assert_false(_clock.record_pong(0, 1000, -1))
	assert_false(_clock.record_pong(0, 3000000, 10))
	assert_false(_clock.is_synchronized)
	_clock.record_pong(1000000, 1100000, 600)
	assert_false(_clock.record_pong(1000000, 1200000, 606))
	assert_false(_clock.record_pong(900000, 1200000, 606))
	assert_false(_clock.record_pong(1000001, 1050000, 606))
	assert_eq(_clock.sample_count, 1)
	assert_eq(_clock.local_tick, 608)
	assert_almost_eq(_clock.rtt_seconds, 0.1, 0.000001)


func test_zero_latency_still_has_jitter_buffer_and_invalid_delta_is_ignored() -> void:
	_clock.record_pong(0, 0, 600)
	assert_eq(_clock.local_tick, 602)
	assert_eq(_clock.advance(0.0, 100000), 602)
	assert_eq(_clock.advance(-STEP, 100000), 602)
	assert_eq(_clock.advance(NAN, 100000), 602)
	assert_eq(_clock.advance(INF, 100000), 602)


func test_reset_removes_old_session_and_can_sync_to_a_lower_server_tick() -> void:
	_clock.record_pong(1000000, 1100000, 600)
	_clock.reset()
	assert_false(_clock.is_synchronized)
	assert_eq(_clock.sample_count, 0)
	assert_eq(_clock.local_tick, 0)
	assert_almost_eq(_clock.rtt_seconds, 0.0, 0.000001)
	assert_eq(_clock.advance(STEP, 2100000), 0)
	assert_almost_eq(_clock.estimated_server_tick(2100000), 0.0, 0.000001)
	assert_true(_clock.record_pong(0, 100000, 0))
	assert_eq(_clock.local_tick, 8)
