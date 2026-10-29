extends GutTest


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func test_default_timeout_and_initial_blacklist_are_resource_data() -> void:
	var config: NetworkConfig = load("res://src/net/default_network.tres") as NetworkConfig
	assert_eq(config.client_timeout_seconds, 10.0)
	assert_eq(config.timeout_factor, 32)
	assert_true(config.blocked_ips.is_empty())
	var session: NetworkSession = NetworkSession.new()
	session.configure(PackedStringArray(["127.0.0.1", "192.0.2.1"]))
	assert_true(session.is_blocked("127.0.0.1"))
	assert_true(session.is_blocked("192.0.2.1"))
	assert_false(session.is_blocked("192.0.2.2"))


func test_ip_validation_normalization_and_listing_do_not_expose_mutable_storage() -> void:
	var session: NetworkSession = NetworkSession.new()
	assert_false(session.ban_ip("localhost"))
	assert_false(session.ban_ip(""))
	assert_false(session.ban_ip("999.1.2.3"))
	assert_true(session.ban_ip(" ::ffff:127.0.0.1 "))
	assert_true(session.is_blocked("127.0.0.1"))
	assert_true(session.ban_ip("2001:DB8::1"))
	assert_true(session.is_blocked("2001:db8::1"))
	assert_eq(session.blacklist(), ["127.0.0.1", "2001:0db8:0000:0000:0000:0000:0000:0001"])
	session.blacklist().clear()
	assert_eq(session.blacklist().size(), 2)
	assert_true(session.unban_ip("::ffff:127.0.0.1"))
	assert_false(session.unban_ip("127.0.0.1"))
	assert_true(session.is_blocked("2001:0db8:0:0:0:0:0:1"))
	assert_true(session.ban_ip("0:0:0:0:0:ffff:7f00:1"))
	assert_true(session.is_blocked("127.0.0.1"))
	assert_true(session.unban_ip("0:0:0:0:0:ffff:127.0.0.1"))
	assert_false(session.is_blocked("127.0.0.1"))


func test_reconnect_uses_case_insensitive_nickname_and_last_server_team() -> void:
	var session: NetworkSession = NetworkSession.new()
	session.admit(42, "Again")
	session.remember_team(42, 2)
	session.forget(42)
	assert_eq(session.team_for("AGAIN"), 2)
	session.admit(43, "again")
	session.remember_team(43, 3)
	assert_eq(session.team_for("Again"), 3)
	session.remember_team(42, 1)
	assert_eq(session.team_for("Again"), 3, "A departed peer cannot overwrite the returning player")
	assert_eq(session.team_for("Unknown", 7), 7)


func test_departure_keeps_session_bans_and_teams_but_new_session_clears_them() -> void:
	var session: NetworkSession = NetworkSession.new()
	session.admit(42, "First")
	session.admit(43, "Second")
	session.remember_team(42, 2)
	session.remember_team(43, 3)
	session.remember_team(43, 0)
	session.remember_team(999, 5)
	session.ban_ip("127.0.0.1")
	session.forget(42)
	assert_true(session.is_blocked("127.0.0.1"))
	assert_eq(session.team_for("Second"), 3)
	session.configure(PackedStringArray(["192.0.2.1"]))
	assert_false(session.is_blocked("127.0.0.1"))
	assert_true(session.is_blocked("192.0.2.1"))
	assert_eq(session.team_for("First"), 1)
	assert_true(session._names.is_empty())
	session.clear()
	assert_true(session.blacklist().is_empty())


func test_lifecycle_accept_close_and_forget_cancel_the_right_deadlines() -> void:
	var lifecycle: PeerLifecycle = PeerLifecycle.new()
	add_child(lifecycle)
	var expired: Array[int] = []
	lifecycle.hello_expired.connect(func(peer: int) -> void: expired.append(peer))
	lifecycle.close_expired.connect(func(peer: int) -> void: expired.append(-peer))
	lifecycle.watch(42, 0.03)
	lifecycle.watch(43, 0.03)
	lifecycle.accepted(42)
	lifecycle.close(43, 0.03)
	await get_tree().create_timer(0.08).timeout
	assert_eq(expired, [-43])
	lifecycle.forget(43)
	lifecycle.watch(44, 0.03)
	lifecycle.close(45, 0.03)
	lifecycle.clear()
	await get_tree().create_timer(0.08).timeout
	assert_eq(expired, [-43])
	assert_true(lifecycle.pending.is_empty())
	assert_true(lifecycle.closing.is_empty())
	lifecycle.free()


func test_client_and_offline_calls_cannot_ban_or_kick_remote_peers() -> void:
	Net.session.clear()
	assert_false(Net.ban_ip("127.0.0.1"))
	assert_false(Net.remove_peer(42, "forged"))
	assert_eq(Net.peer_ip(42), "")
	assert_true(Net.session.blacklist().is_empty())


func test_watchdog_expires_exactly_ten_seconds_after_last_packet_per_peer() -> void:
	var lifecycle: PeerLifecycle = PeerLifecycle.new()
	add_child(lifecycle)
	lifecycle.configure(NetworkConfig.new())
	var expired: Array[int] = []
	lifecycle.peer_timed_out.connect(func(peer: int) -> void: expired.append(peer))
	lifecycle.track(42, 0)
	lifecycle.track(43, 0)
	lifecycle.received(43, 5000000)
	lifecycle.received(999, 9000000)
	lifecycle.expire(9999999)
	assert_true(expired.is_empty())
	lifecycle.expire(10000000)
	assert_eq(expired, [42])
	lifecycle.expire(14999999)
	assert_eq(expired, [42])
	lifecycle.expire(15000000)
	assert_eq(expired, [42, 43])
	lifecycle.expire(30000000)
	assert_eq(expired, [42, 43], "Each timeout fires once; unknown packets do not admit a peer")
	lifecycle.free()


func test_activity_never_moves_backwards_and_disconnect_cancels_old_deadlines() -> void:
	var lifecycle: PeerLifecycle = PeerLifecycle.new()
	add_child(lifecycle)
	lifecycle.configure(NetworkConfig.new())
	lifecycle.track(42, 5000000)
	lifecycle.received(42, 1)
	assert_eq(lifecycle.activity[42], 5000000)
	lifecycle.forget(42)
	lifecycle.received(42, 9000000)
	assert_true(lifecycle.activity.is_empty())
	lifecycle.track(43, 0)
	lifecycle.clear()
	lifecycle.expire(20000000)
	assert_true(lifecycle.activity.is_empty())
	assert_true(lifecycle._watchdog.is_stopped())
	lifecycle.free()


func test_blacklist_commands_require_current_admin_authentication() -> void:
	var previous: String = Game.admin_password
	Game.admin_password = "session_test_secret"
	var chat: NetworkChat = NetworkChat.new()
	add_child(chat)
	Net.session.ban_ip("127.0.0.1")
	chat._command(1, "/unban 127.0.0.1")
	assert_true(Net.session.is_blocked("127.0.0.1"))
	assert_true(chat.admin.login(1, Game.admin_password, Game.admin_password))
	chat._command(1, "/unban 127.0.0.1")
	assert_false(Net.session.is_blocked("127.0.0.1"))
	Net.session.ban_ip("127.0.0.1")
	chat.admin.forget(1)
	chat._command(1, "/unban 127.0.0.1")
	assert_true(Net.session.is_blocked("127.0.0.1"))
	chat.free()
	Net.session.clear()
	Game.admin_password = previous
