extends GutTest

var _sim: NetSim
var _seen: Array[int] = []
var _peers: Array[int] = []


func before_each() -> void:
	_sim = NetSim.new()
	_sim.profile = NetSimConfig.new()
	_sim.configure(1)
	_sim.random.seed = 412
	_sim.packet_delivered.connect(_record)
	_seen.clear()
	_peers.clear()


func after_each() -> void:
	_sim.free()
	Net.disconnect_all()
	Net.time_sync.configure_simulation(0, 0.0)


func _record(packet: PackedByteArray, _extra: PackedByteArray, peer_id: int) -> void:
	_seen.append(packet[0])
	_peers.append(peer_id)


func test_half_rtt_copies_payload_and_routes_recipient() -> void:
	_sim.profile.rtt_ms = 100
	var packet: PackedByteArray = PackedByteArray([42])
	_sim.submit(packet, PackedByteArray(), 7, 1000)
	packet[0] = 99
	_sim.flush(50999)
	assert_eq(_seen.size(), 0)
	_sim.flush(51000)
	assert_eq(_seen, [42])
	assert_eq(_peers, [7])


func test_jitter_is_bounded_reproducible_and_can_change_delivery_order() -> void:
	_sim.profile.rtt_ms = 100
	_sim.profile.jitter_ms = 20
	for value: int in range(32):
		_sim.submit(PackedByteArray([value]), PackedByteArray(), 1, 1000)
	_sim.flush(30999)
	assert_eq(_seen.size(), 0)
	_sim.flush(71000)
	assert_eq(_seen.size(), 32)
	assert_ne(_seen, range(32))
	var expected: Array[int] = _seen.duplicate()
	_seen.clear()
	_sim.clear()
	_sim.random.seed = 412
	for value: int in range(32):
		_sim.submit(PackedByteArray([value]), PackedByteArray(), 1, 1000)
	_sim.flush(71000)
	assert_eq(_seen, expected)


func test_duplicates_do_not_change_payload_or_destination() -> void:
	_sim.profile.duplicate_percent = 100.0
	_sim.submit(PackedByteArray([8]), PackedByteArray(), 2, 1000)
	assert_eq(_seen, [8, 8])
	assert_eq(_peers, [2, 2])
	assert_eq(_sim.duplicated, 1)
	assert_eq(_sim.delivered, 2)


func test_reordering_is_due_time_order_and_never_blocks_a_later_packet() -> void:
	_sim.profile.rtt_ms = 100
	_sim.profile.reorder_percent = 100.0
	_sim.submit(PackedByteArray([1]), PackedByteArray(), 1, 1000)
	_sim.profile.reorder_percent = 0.0
	_sim.submit(PackedByteArray([2]), PackedByteArray(), 1, 2000)
	_sim.flush(52000)
	assert_eq(_seen, [2])
	_sim.flush(101000)
	assert_eq(_seen, [2, 1])
	assert_eq(_sim.reordered, 1)


func test_equal_deadlines_preserve_submission_order() -> void:
	_sim.profile.rtt_ms = 100
	for value: int in range(32):
		_sim.submit(PackedByteArray([value]), PackedByteArray(), 1, 1000)
	_sim.flush(51000)
	assert_eq(_seen, range(32))


func test_loss_and_overflow_are_bounded_and_clear_cancels_old_session() -> void:
	_sim.profile.loss_percent = 100.0
	_sim.profile.duplicate_percent = 100.0
	assert_false(_sim.submit(PackedByteArray([1])))
	assert_eq(_sim.duplicated, 0)
	_sim.profile.loss_percent = 0.0
	_sim.profile.rtt_ms = 100
	for value: int in range(NetSim.CAPACITY / 2):
		assert_true(_sim.submit(PackedByteArray([value]), PackedByteArray(), 1, 1000))
	assert_false(_sim.submit(PackedByteArray([2]), PackedByteArray(), 1, 1000))
	assert_eq(_sim.overflowed, 1)
	assert_eq(_sim._slots.size(), NetSim.CAPACITY)
	_sim.clear()
	_sim.flush(1000000)
	assert_eq(_seen.size(), 0)


func test_discarding_one_peer_keeps_other_recipients() -> void:
	_sim.profile.rtt_ms = 100
	_sim.submit(PackedByteArray([1]), PackedByteArray(), 2, 1000)
	_sim.submit(PackedByteArray([2]), PackedByteArray(), 3, 1000)
	_sim.discard_peer(2)
	_sim.flush(1000000)
	assert_eq(_seen, [2])
	assert_eq(_peers, [3])


func test_invalid_profiles_and_payloads_do_not_enter_queue() -> void:
	for invalid: float in [-1.0, 101.0, NAN, INF]:
		_sim.profile.loss_percent = invalid
		assert_false(_sim.submit(PackedByteArray([1])))
	_sim.profile.loss_percent = 0.0
	_sim.profile.rtt_ms = NetSimConfig.MAX_DELAY_MS + 1
	assert_false(_sim.submit(PackedByteArray([1])))
	_sim.profile.rtt_ms = 0
	assert_false(_sim.submit(PackedByteArray([1, 2])))
	assert_eq(_sim.submitted, 0)


func test_link_profiles_are_isolated_validated_and_removed_on_departure() -> void:
	var first: NetSimConfig = NetSimConfig.new()
	first.rtt_ms = 100
	var second: NetSimConfig = NetSimConfig.new()
	second.rtt_ms = 200
	Net.time_sync._profiles[11] = first
	Net.time_sync._profiles[12] = second
	assert_eq(Net.time_sync.profile_for(11), first)
	assert_eq(Net.time_sync.profile_for(12), second)
	Net.time_sync._peer_left(11)
	assert_eq(Net.time_sync.profile_for(11), Net.time_sync.profile)
	assert_eq(Net.time_sync.profile_for(12), second)
	Net.time_sync.set_simulation(100, 0.0, 0, 0.0, 0.0)
	assert_false(Net.time_sync._profiles.has(0), "Unadmitted sender cannot assign a link profile")


func test_server_console_overrides_all_downlinks_and_zero_disables_them() -> void:
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(socket.bind(0, "127.0.0.1"), OK)
	var port: int = socket.get_local_port()
	socket.close()
	assert_eq(Net.start_server(port, 1, false), OK)
	var client_profile: NetSimConfig = NetSimConfig.new()
	client_profile.rtt_ms = 200
	Net.time_sync._profiles[11] = client_profile
	var console: DebugConsole = DebugConsole.new()
	console.execute_command("net_sim 100 5 20 10 10")
	assert_eq(Net.time_sync.profile_for(11), Net.time_sync.profile)
	assert_eq(Net.time_sync.profile_for(12), Net.time_sync.profile)
	assert_eq(Net.time_sync.profile_for(11).rtt_ms, 100)
	console.execute_command("net_sim 0 0")
	assert_eq(Net.time_sync.profile_for(11).rtt_ms, 0)
	assert_eq(Net.time_sync.profile_for(11).loss_percent, 0.0)
	Net.disconnect_all()
	assert_false(Net.time_sync._server_override)


func test_console_extended_profile_and_atomic_validation() -> void:
	var console: DebugConsole = DebugConsole.new()
	assert_has(console.execute_command("net_sim 200 5 20 3 7"), "jitter=20")
	var cfg: NetSimConfig = Net.time_sync.profile
	assert_eq(cfg.rtt_ms, 200)
	assert_eq(cfg.jitter_ms, 20)
	assert_eq(cfg.duplicate_percent, 3.0)
	assert_eq(cfg.reorder_percent, 7.0)
	for invalid: String in ["net_sim 2001 0", "net_sim 0 0 -1", "net_sim 0 0 0 nan", "net_sim 0 0 0 0 101"]:
		assert_has(console.execute_command(invalid), "Error:")
		assert_eq(Net.time_sync.profile, cfg)
	console.execute_command("net_sim 0 0")
	assert_eq(Net.time_sync.profile.jitter_ms, 0)
	assert_eq(Net.time_sync.profile.duplicate_percent, 0.0)
	assert_eq(Net.time_sync.profile.reorder_percent, 0.0)
