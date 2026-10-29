extends GutTest

var _delay: NetSim
var _received: Array[PackedByteArray] = []


func before_each() -> void:
	_delay = NetSim.new()
	_delay.configure(2, 1)
	_delay.random.seed = 460
	_delay.packet_delivered.connect(_record)
	_received.clear()
	Net.time_sync.configure_simulation(0, 0.0)


func after_each() -> void:
	_delay.free()
	Net.time_sync.configure_simulation(0, 0.0)


func test_zero_delay_delivers_immediately_and_keeps_order() -> void:
	assert_true(_delay.submit(PackedByteArray([1, 2]), PackedByteArray([3])))
	assert_eq(_received.size(), 1)
	assert_eq(_received[0], PackedByteArray([1, 2, 3]))
	assert_eq(_delay.delivered, 1)


func test_120ms_rtt_holds_each_direction_for_60ms_and_copies_packet() -> void:
	Net.time_sync.configure_simulation(120, 0.0)
	var before: int = Time.get_ticks_usec()
	var packet: PackedByteArray = PackedByteArray([1, 2])
	assert_true(_delay.submit(packet, PackedByteArray([3])))
	packet[0] = 99
	_delay.flush(before + 59000)
	assert_eq(_received.size(), 0)
	_delay.flush(Time.get_ticks_usec() + 61000)
	assert_eq(_received.size(), 1)
	assert_eq(_received[0], PackedByteArray([1, 2, 3]))


func test_loss_overflow_and_clear_cannot_deliver_stale_packets() -> void:
	Net.time_sync.configure_simulation(120, 100.0)
	assert_false(_delay.submit(PackedByteArray([1, 2]), PackedByteArray([3])))
	assert_eq(_delay.dropped, 1)
	Net.time_sync.configure_simulation(120, 0.0)
	for index: int in range(NetSim.CAPACITY):
		assert_true(_delay.submit(PackedByteArray([index, 2]), PackedByteArray([3])))
	assert_false(_delay.submit(PackedByteArray([1, 2]), PackedByteArray([3])))
	assert_eq(_delay.dropped, 2)
	_delay.clear()
	_delay.flush(Time.get_ticks_usec() + 200000)
	assert_eq(_received.size(), 0)
	assert_false(_delay.submit(PackedByteArray([1]), PackedByteArray([3])))


func test_two_percent_loss_is_applied_to_game_packets() -> void:
	Net.time_sync.configure_simulation(0, 2.0)
	for index: int in range(1000):
		_delay.submit(PackedByteArray([1, 2]), PackedByteArray([3]))
	assert_gt(_delay.dropped, 0)
	assert_lt(_delay.dropped, 60)
	assert_eq(_delay.delivered + _delay.dropped, 1000)


func _record(packet: PackedByteArray, extra: PackedByteArray, _peer_id: int) -> void:
	var copy: PackedByteArray = packet.duplicate()
	copy.append_array(extra)
	_received.append(copy)
