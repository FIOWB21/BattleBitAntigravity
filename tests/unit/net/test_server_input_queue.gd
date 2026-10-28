extends GutTest

var _config: NetworkConfig
var _queue: ServerInputQueue


func before_each() -> void:
	_config = NetworkConfig.new()
	_queue = ServerInputQueue.new()
	_queue.configure(_config, 60)


func test_order_duplicates_and_exactly_one_input_per_server_tick() -> void:
	for tick: int in [104, 101, 103, 102]:
		assert_true(_queue.enqueue(_frame(tick), 100))
	assert_false(_queue.enqueue(_frame(102), 100))
	assert_eq(_queue.pending_count, 4)
	for tick: int in range(101, 105):
		var consumed: PlayerInput = _queue.consume(tick - 1)
		assert_eq(consumed.tick, tick - 1, "Simulation uses server time")
		assert_eq(_queue.last_input_tick, tick)
		assert_null(_queue.consume(tick - 1), "Cannot step twice on one server tick")
		assert_eq(_queue.pending_count, 104 - tick)
	assert_false(_queue.enqueue(_frame(103), 104))


func test_empty_queue_repeats_exactly_five_ticks_then_stops_all_actions() -> void:
	var inp: PlayerInput = _frame(100)
	inp.move = Vector2.RIGHT
	inp.buttons = PlayerInput.BTN_FIRE | PlayerInput.BTN_SPRINT
	inp.yaw = 1.0
	assert_true(_queue.enqueue(inp, 100))
	_queue.consume(100)
	for tick: int in range(101, 106):
		var repeated: PlayerInput = _queue.consume(tick)
		assert_eq(repeated.move, inp.move)
		assert_eq(repeated.buttons, inp.buttons)
		assert_eq(repeated.tick, tick)
	var stopped: PlayerInput = _queue.consume(106)
	assert_eq(stopped.move, Vector2.ZERO)
	assert_eq(stopped.buttons, 0)
	assert_eq(stopped.yaw, 1.0)
	assert_true(_queue.enqueue(_frame(110), 107))
	_queue.consume(107)
	assert_eq(_queue.last_input_tick, 110)
	assert_eq(_queue.repeated_ticks, 0)


func test_future_and_old_window_boundaries_are_inclusive() -> void:
	assert_false(_queue.enqueue(_frame(39), 100))
	assert_true(_queue.enqueue(_frame(40), 100))
	assert_true(_queue.enqueue(_frame(160), 100))
	assert_false(_queue.enqueue(_frame(161), 100))
	_queue.consume(101)
	assert_eq(_queue.last_input_tick, 160, "Stale queued input is pruned before simulation")
	assert_eq(_queue.pending_count, 0)


func test_move_speedhack_and_nonfinite_values_are_rejected() -> void:
	var inp: PlayerInput = _frame(100)
	inp.move = Vector2.ONE
	assert_false(_queue.enqueue(inp, 100))
	inp.move = Vector2(1.011, 0.0)
	assert_false(_queue.enqueue(inp, 100))
	inp.move = Vector2(1.009, 0.0)
	assert_true(_queue.enqueue(inp, 100))
	inp.tick += 1
	inp.move = Vector2(NAN, 0.0)
	assert_false(_queue.enqueue(inp, 100))
	assert_eq(_queue.pending_count, 1)


func test_redundancy_recovers_five_lost_packets_and_ignores_retransmits() -> void:
	var history: InputHistory = InputHistory.new()
	history.configure(_config.input_history_count)
	for tick: int in range(100, 106):
		assert_true(history.push(_frame(tick)))
	assert_eq(_queue.receive(history.packet, 105), 6)
	assert_eq(_queue.receive(history.packet, 105), 0)
	for tick: int in range(100, 106):
		_queue.consume(tick + 6)
		assert_eq(_queue.last_input_tick, tick)
	assert_eq(_queue.pending_count, 0)


func test_packet_flood_cannot_grow_queue_or_speed_up_consumption() -> void:
	_config.input_queue_capacity = 8
	_queue.configure(_config, 60)
	for tick: int in range(100, 120):
		assert_eq(_queue.enqueue(_frame(tick), 100), tick < 108)
	assert_eq(_queue.pending_count, 8)
	_queue.consume(100)
	assert_eq(_queue.pending_count, 7)
	assert_eq(_queue.last_input_tick, 100)
	assert_null(_queue.consume(99))
	assert_null(_queue.consume(100))


func test_malformed_packets_and_zero_tick_padding_are_ignored() -> void:
	assert_eq(_queue.receive(PackedByteArray(), 100), 0)
	var history: InputHistory = InputHistory.new()
	history.configure(_config.input_history_count)
	assert_true(history.push(_frame(100)))
	assert_eq(_queue.receive(history.packet, 100), 1)
	assert_eq(_queue.pending_count, 1)
	history.packet.resize(history.packet.size() + 1)
	assert_eq(_queue.receive(history.packet, 100), 0)


func test_queue_instances_outputs_and_reset_do_not_share_mutable_frame() -> void:
	var other: ServerInputQueue = ServerInputQueue.new()
	other.configure(_config, 60, 2.0)
	var inp: PlayerInput = _frame(100)
	assert_true(_queue.enqueue(inp, 100))
	inp.move = Vector2.RIGHT
	assert_eq(_queue.consume(100).move, Vector2.UP)
	assert_eq(other.consume(100).move, Vector2.ZERO)
	assert_eq(other.consume(101).yaw, 2.0)
	_queue.configure(_config, 60)
	assert_eq(_queue.last_input_tick, 0)
	assert_eq(_queue.pending_count, 0)
	assert_eq(_queue.consume(1).move, Vector2.ZERO)


func _frame(tick: int) -> PlayerInput:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = tick
	inp.move = Vector2.UP
	return inp
