extends GutTest

var _original_config: NetworkConfig


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_original_config = Net.config
	Net.config = _original_config.duplicate() as NetworkConfig
	Net.local_nickname = "LocalHost"
	Net.password = ""
	Game.detect_runtime_flags(PackedStringArray(), false)


func after_each() -> void:
	Net.disconnect_all()
	Net.config = _original_config
	Net.local_nickname = "Player"
	Net.password = ""
	await get_tree().process_frame


func test_listen_server_admits_host_and_disconnect_emits_left_once() -> void:
	var joined: Array[int] = []
	var left: Array[int] = []
	var on_joined: Callable = func(id: int, _nickname: String) -> void: joined.append(id)
	var on_left: Callable = func(id: int) -> void: left.append(id)
	Net.peer_joined.connect(on_joined)
	Net.peer_left.connect(on_left)
	assert_eq(Net.start_server(_port(), 4), OK)
	assert_true(Net.is_connected)
	assert_true(Game.is_server)
	assert_eq(Net.nicknames.get(1), "LocalHost")
	assert_eq(joined, [1])
	Net.disconnect_all()
	Net.disconnect_all()
	assert_eq(left, [1])
	assert_true(Net.nicknames.is_empty())
	assert_false(Net.is_connected)
	assert_true(Net.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	Net.peer_joined.disconnect(on_joined)
	Net.peer_left.disconnect(on_left)


func test_tick_only_advances_on_active_server_and_resets_on_restart() -> void:
	Net._physics_process(1.0 / 60.0)
	assert_eq(Net.tick, 0)
	assert_eq(Net.start_server(_port(), 4, false), OK)
	assert_true(Net.nicknames.is_empty(), "Dedicated server has no host player")
	Net._physics_process(1.0 / 60.0)
	assert_eq(Net.tick, 1)
	Net._physics_process(1.0 / 60.0)
	assert_eq(Net.tick, 2)
	Net.disconnect_all()
	assert_eq(Net.tick, 0)
	Net._physics_process(1.0 / 60.0)
	assert_eq(Net.tick, 0)


func test_invalid_parameters_never_install_a_transport() -> void:
	for port: int in [0, -1, 65536]:
		assert_eq(Net.start_server(port, 4), ERR_INVALID_PARAMETER)
		assert_eq(Net.join("127.0.0.1", port), ERR_INVALID_PARAMETER)
	for count: int in [0, -1, 4096]:
		assert_eq(Net.start_server(7777, count), ERR_INVALID_PARAMETER)
	assert_eq(Net.join("   ", 7777), ERR_INVALID_PARAMETER)
	Net.local_nickname = "!"
	assert_eq(Net.start_server(7777, 4), ERR_INVALID_PARAMETER)
	assert_eq(Net.join("127.0.0.1", 7777), ERR_INVALID_PARAMETER)
	assert_true(Net.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	assert_false(Net.is_connected)


func test_repeated_start_and_join_do_not_replace_active_server() -> void:
	var connections: int = Net.multiplayer.peer_connected.get_connections().size()
	for attempt: int in range(3):
		assert_eq(Net.start_server(_port(), 4), OK)
		var peer: MultiplayerPeer = Net.multiplayer.multiplayer_peer
		assert_eq(Net.start_server(7777, 4), ERR_ALREADY_IN_USE)
		assert_eq(Net.join("127.0.0.1", 7777), ERR_ALREADY_IN_USE)
		assert_eq(Net.multiplayer.multiplayer_peer, peer)
		Net.disconnect_all()
	assert_eq(Net.multiplayer.peer_connected.get_connections().size(), connections)


func test_unreachable_server_times_out_once_and_allows_retry() -> void:
	Net.config.handshake_timeout_seconds = 0.1
	var failures: Array[int] = [0]
	var callback: Callable = func() -> void: failures[0] += 1
	Net.connection_failed.connect(callback)
	assert_eq(Net.join("127.0.0.1", _port()), OK)
	assert_false(Net.is_connected, "Transport connection is not admission")
	assert_false(Game.is_server_or_offline(Net.multiplayer))
	Net._physics_process(1.0 / 60.0)
	assert_eq(Net.tick, 0)
	await get_tree().create_timer(0.25).timeout
	assert_eq(failures[0], 1)
	assert_eq(Net.last_error, "connection_failed")
	assert_true(Net.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	assert_eq(Net.start_server(_port(), 4), OK)
	assert_eq(Net.last_error, "")
	Net.connection_failed.disconnect(callback)


func test_local_hello_and_welcome_cannot_admit_an_offline_peer() -> void:
	Net.hello(1, "Spoofed")
	Net.welcome(1)
	Net.kick("forged")
	assert_true(Net.nicknames.is_empty())
	assert_false(Net.is_connected)
	assert_eq(Net.last_error, "")


func _port() -> int:
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(socket.bind(0, "127.0.0.1"), OK)
	var result: int = socket.get_local_port()
	socket.close()
	return result
