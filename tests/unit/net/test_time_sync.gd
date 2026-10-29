extends GutTest


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func after_each() -> void:
	Net.disconnect_all()
	Net.time_sync.configure_simulation(0, 0.0)
	Game.reset_debug()


func test_disconnect_clears_clock_measured_ping_and_reusable_timers() -> void:
	Net.clock.configure(Net.config, 60)
	Net.clock.record_pong(0, 100000, 100)
	Game.debug["ping_ms"] = 100.0
	var children: int = Net.time_sync.get_child_count()
	Net.disconnect_all()
	assert_eq(Net.tick, 0)
	assert_false(Net.clock.is_synchronized)
	assert_eq(Net.clock.sample_count, 0)
	assert_almost_eq(float(Game.debug["ping_ms"]), 0.0, 0.000001)
	assert_true(Net.time_sync._interval.is_stopped())
	assert_eq(Net.time_sync.outbound.delivered, 0)
	assert_eq(children, 2)
	assert_eq(Net.time_sync.get_child_count(), children)


func test_offline_and_unmatched_pong_never_produce_a_measurement() -> void:
	Net.time_sync.ping(123)
	Net.time_sync.pong(123, 999)
	assert_false(Net.clock.is_synchronized)
	assert_eq(Net.clock.sample_count, 0)
	assert_eq(Net.tick, 0)


func test_expired_probes_are_removed() -> void:
	var now: int = Time.get_ticks_usec() + 3000000
	var stale: int = now - 2500000
	var fresh: int = now - 100000
	Net.time_sync._pending[stale] = -1
	Net.time_sync._pending[fresh] = -1
	Net.time_sync._expire_probes(now)
	assert_false(Net.time_sync._pending.has(stale))
	assert_true(Net.time_sync._pending.has(fresh))
	assert_eq(Net.time_sync._pending.size(), 1)


func test_disconnect_cancels_delayed_callbacks_from_the_previous_session() -> void:
	Net.time_sync._active = true
	Net.time_sync._pending[123] = 100
	Net.time_sync.configure_simulation(100, 0.0)
	var packet: PackedByteArray = PackedByteArray()
	packet.resize(NetTimeSync.PROBE_BYTES)
	Net.time_sync.outbound.submit(packet)
	Net.disconnect_all()
	await get_tree().create_timer(0.05).timeout
	assert_eq(Net.clock.sample_count, 0)
	assert_true(Net.time_sync._pending.is_empty())
	Net.time_sync.outbound.flush(Time.get_ticks_usec() + 1000000)
	assert_eq(Net.time_sync.outbound.delivered, 0)


func test_net_sim_does_not_fabricate_ping_and_rejects_invalid_values() -> void:
	var console: DebugConsole = DebugConsole.new()
	Game.debug["ping_ms"] = 42.0
	console.execute_command("net_sim 100 0")
	assert_eq(Net.time_sync.simulated_rtt_ms, 100)
	assert_almost_eq(float(Game.debug["ping_ms"]), 42.0, 0.000001)
	for command: String in ["net_sim -1 0", "net_sim 100 101", "net_sim 100 -1", "net_sim 100 nan"]:
		console.execute_command(command)
		assert_eq(Net.time_sync.simulated_rtt_ms, 100)
		assert_almost_eq(Net.time_sync.simulated_loss_percent, 0.0, 0.000001)


func test_overlay_uses_measured_ping_and_exposes_clock_diagnostics() -> void:
	var overlay: DebugOverlay = preload("res://src/ui/debug_overlay.tscn").instantiate() as DebugOverlay
	Game.debug["ping_ms"] = 104.0
	var text: String = overlay.format_stats_text()
	assert_has(text, "Ping: 104 ms")
	assert_has(text, "Tick:")
	assert_has(text, "Server:")
	assert_has(text, "Lead:")
	overlay.free()
