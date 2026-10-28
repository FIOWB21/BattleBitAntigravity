extends GutTest

var _history: FireHistory


func before_each() -> void:
	_history = FireHistory.new()
	_history.configure(NetworkConfig.new(), 60)


func test_requires_valid_tick_and_reproducible_seed() -> void:
	for tick: int in [-1, 0, 39, 161]:
		assert_false(_history.request(tick, FireHistory.shot_seed(tick, 7), 7, 100))
	assert_false(_history.request(100, -1, 7, 100))
	assert_false(_history.request(100, FireHistory.shot_seed(100, 8), 7, 100))
	assert_true(_history.request(100, FireHistory.shot_seed(100, 7), 7, 100))


func test_request_waits_for_server_input_in_either_arrival_order() -> void:
	assert_true(_history.request(105, FireHistory.shot_seed(105, 7), 7, 100))
	assert_null(_history.take_ready(100))
	_history.slot(105).recorded = true
	assert_eq(_history.take_ready(100).tick, 105)
	_history.slot(106).recorded = true
	assert_true(_history.request(106, FireHistory.shot_seed(106, 7), 7, 100))
	assert_eq(_history.take_ready(100).tick, 106)


func test_duplicates_and_replay_after_consumption_are_rejected() -> void:
	var seed: int = FireHistory.shot_seed(100, 7)
	assert_true(_history.request(100, seed, 7, 100))
	assert_false(_history.request(100, seed, 7, 100))
	_history.slot(100).recorded = true
	assert_not_null(_history.take_ready(100))
	assert_false(_history.request(100, seed, 7, 100))
	assert_null(_history.take_ready(100))


func test_ready_requests_are_sorted_and_expire_without_replaying() -> void:
	for tick: int in [102, 100, 101]:
		assert_true(_history.request(tick, FireHistory.shot_seed(tick, 7), 7, 100))
		_history.slot(tick).recorded = true
	assert_eq(_history.take_ready(100).tick, 100)
	assert_eq(_history.take_ready(100).tick, 101)
	assert_null(_history.take_ready(200))
	assert_true(_history.slot(102).consumed)


func test_flood_is_bounded_and_does_not_erase_live_records() -> void:
	var size: int = _history.frames.size()
	for tick: int in range(40, 161):
		assert_true(_history.request(tick, FireHistory.shot_seed(tick, 7), 7, 100))
	for tick: int in range(40, 161):
		assert_false(_history.request(tick, FireHistory.shot_seed(tick, 7), 7, 100))
	assert_eq(_history.frames.size(), size)
	assert_false(_history.request(100 + size, FireHistory.shot_seed(100 + size, 7), 7, 100))
	assert_true(_history.slot(100).requested)


func test_ring_reuses_slots_only_after_window_and_does_not_share_state() -> void:
	var frame: FireFrame = _history.slot(100)
	frame.allowed = true
	frame.aim.origin = Vector3.ONE
	frame.recorded = true
	var later: int = 100 + _history.frames.size()
	assert_eq(_history.slot(later), frame)
	assert_false(frame.recorded)
	assert_false(frame.allowed)
	_history.configure(NetworkConfig.new(), 60)
	assert_ne(_history.slot(100), frame)


func test_missing_input_expires_and_acknowledges_the_cosmetic_request() -> void:
	assert_true(_history.request(100, FireHistory.shot_seed(100, 7), 7, 100))
	assert_null(_history.take_ready(161))
	assert_true(_history.slot(100).consumed)
	assert_eq(_history.expired_tick, 100)
