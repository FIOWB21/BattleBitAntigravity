# Isolated integration fixture: actual ENet peers and the production Net autoload.
extends SceneTree

const TIMEOUT_SECONDS: float = 15.0
var _net: Node
var _options: Dictionary[String, String] = {}
var _finished: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_net = root.get_node("Net")
	for arg: String in OS.get_cmdline_user_args():
		_options[arg.get_slice("=", 0)] = arg.substr(arg.find("=") + 1)
	_net.config = _net.config.duplicate()
	_net.config.handshake_timeout_seconds = 1.0 if _options.get("--role", "client") == "server" else 3.0
	_net.password = _options.get("--password", "")
	if _options.get("--role", "client") == "server":
		await _server()
	else:
		await _client()


func _server() -> void:
	_net.peer_joined.connect(func(id: int, nickname: String) -> void:
		print("WORKER ACCEPT id=", id, " nickname=", nickname))
	_net.peer_left.connect(func(id: int) -> void: print("WORKER LEFT id=", id))
	var result: Error = _net.start_server(int(_options["--port"]), 8, false)
	if result != OK:
		print("WORKER START FAILED ", result)
		quit(1)
		return
	print("WORKER READY")
	var deadline: int = Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(_options["--stop-file"]):
			break
		await create_timer(0.05).timeout
	print("WORKER SERVER tick=", _net.tick, " remaining=", _net.nicknames.size())
	_net.disconnect_all()
	await process_frame
	quit(0)


func _client() -> void:
	_net.local_nickname = "ValidClient"
	var mode: String = _options.get("--mode", "normal")
	if mode != "normal":
		var callback: Callable = Callable(_net, "_on_transport_connected")
		_net.multiplayer.connected_to_server.disconnect(callback)
		_net.multiplayer.connected_to_server.connect(_send_custom_hello)
	else:
		_net.local_nickname = _options.get("--nickname", "ClientOne")
	_net.connected_to_server.connect(_accepted)
	_net.connection_failed.connect(_rejected)
	var result: Error = _net.join("127.0.0.1", int(_options["--port"]))
	if result != OK:
		print("WORKER JOIN FAILED ", result)
		quit(1)
		return
	await create_timer(TIMEOUT_SECONDS).timeout
	if not _finished:
		print("WORKER TIMEOUT")
		_net.disconnect_all()
		quit(1)


func _send_custom_hello() -> void:
	if _options.get("--mode", "") == "silent":
		return
	_net.rpc_id(1, "hello", int(_options.get("--version", str(_net.PROTOCOL_VERSION))),
		_options.get("--nickname", "ClientOne"), _net.password)


func _accepted() -> void:
	print("WORKER CONNECTED")
	_net.rpc_id(1, "hello", _net.PROTOCOL_VERSION, _net.local_nickname, _net.password)
	await create_timer(float(_options.get("--hold", "0.1"))).timeout
	if not _finished:
		_finished = true
		_net.disconnect_all()
		print("WORKER CLIENT CLOSED")
		quit(0)


func _rejected() -> void:
	print("WORKER REJECTED reason=", _net.last_error)
	_finished = true
	quit(0)
