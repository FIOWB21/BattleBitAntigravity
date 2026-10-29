# Real menu/ENet fixture; blackhole keeps the UDP socket open without polling it.
extends SceneTree

const TIMEOUT_SECONDS: float = 45.0
var _options: Dictionary[String, String] = {}
var _net: Node
var _menu: Control
var _abandoned: ENetMultiplayerPeer
var _failed: bool = false
var _assigned: bool = false
var _previous: String = ""
var _command: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.low_processor_usage_mode_sleep_usec = 1000
	for arg: String in OS.get_cmdline_user_args():
		_options[arg.get_slice("=", 0)] = arg.substr(arg.find("=") + 1)
	_net = root.get_node("Net")
	var game: Node = root.get_node("Game")
	var server: bool = _options.has("--server-role")
	game.is_dedicated = server and not _options.has("--host")
	game.server_port = int(_options["--port"])
	game.max_clients = int(_options.get("--max", "2"))
	game.server_password = _options.get("--password", "")
	game.admin_password = "fixture_admin"
	_net.config = _net.config.duplicate()
	if _options.has("--blocked"):
		_net.config.blocked_ips = PackedStringArray(["127.0.0.1"])
	_setup_menu(server, game)
	print("SESSION READY server=", server)
	await _observe(server)
	_finish()


func _setup_menu(server: bool, game: Node) -> void:
	_menu = load("res://src/ui/main_menu.tscn").instantiate() as Control
	_menu.name = "MainMenu"
	root.add_child(_menu)
	_menu.port.value = game.server_port
	_menu.nickname.text = _options.get("--nickname", "Admin")
	_menu.password_field.text = game.server_password
	if _options.has("--host"):
		_menu.host_button.pressed.emit()
	elif not server:
		_net.connection_failed.connect(_rejected)
		_menu.join_button.pressed.emit()
	_menu.map_loader.chat.admin.login(1, game.admin_password, game.admin_password)
	_menu.map_loader.chat.notice_received.connect(func(text: String) -> void: print("SESSION NOTICE ", text))


func _observe(server: bool) -> void:
	var deadline: int = Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 1000.0)
	var dropped: bool = false
	var quiet_started: int = -1
	var reported: bool = false
	while Time.get_ticks_msec() < deadline and not _failed:
		if FileAccess.file_exists(_options["--stop-file"]):
			break
		if _abandoned == null:
			_record(server)
		if server:
			_control()
		elif _options.has("--no-probes") and _menu.map_loader.players.actors.size() > 0:
			if quiet_started < 0:
				_net.time_sync._interval.stop()
				quiet_started = Time.get_ticks_msec()
			if not reported and Time.get_ticks_msec() - quiet_started >= 11000:
				print("SESSION TRAFFIC ALIVE")
				reported = true
		elif _options.has("--vanish") and not dropped and _net.is_connected \
				and _menu.map_loader.players.actors.size() > 0:
			await create_timer(0.5).timeout
			_blackhole()
			dropped = true
		await create_timer(0.05).timeout


func _record(server: bool) -> void:
	var players: Node = _menu.map_loader.players
	var teams: Dictionary[String, int] = {}
	for id: int in players.actors:
		var actor: Node = players.actors[id]
		if server and id != 1 and not _assigned:
			actor.team_id = 2
			actor.affiliation.team_id = 2
			_assigned = true
		teams[str(id)] = actor.team_id
	var state: Dictionary = {"actors": players.actors.size(), "ready": players.ready_peers.size(),
		"slots": players._slots.size(), "names": _net.nicknames.size(), "teams": teams,
		"tracks": players.lag_compensator.tracks.size(), "snapshots": players.snapshots._actors.size(),
		"respawns": players.respawns.deadlines.size(), "pending": _net.lifecycle.pending.size(),
		"closing": _net.lifecycle.closing.size()}
	var serialized: String = JSON.stringify(state)
	if serialized != _previous:
		_previous = serialized
		state["time"] = Time.get_ticks_msec()
		print("SESSION STATE ", JSON.stringify(state))


func _control() -> void:
	var path: String = _options.get("--control", "")
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var command: String = FileAccess.get_file_as_string(path)
	if command == _command:
		return
	_command = command
	if command == "blackhole":
		_blackhole()
	else:
		_menu.map_loader.chat._command(1, command)
		print("SESSION COMMAND APPLIED")


func _blackhole() -> void:
	_net.time_sync.stop()
	_net.set("is_connected", false)
	_net.set_physics_process(false)
	_menu.process_mode = Node.PROCESS_MODE_DISABLED
	_abandoned = _net.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	_net._peer = null
	_net.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	print("SESSION BLACKHOLE time=", Time.get_ticks_msec())


func _rejected() -> void:
	_failed = true
	print("SESSION REJECTED reason=", _net.last_error)


func _finish() -> void:
	_net.disconnect_all()
	if _abandoned != null:
		_abandoned.close()
		_abandoned = null
	await process_frame
	print("SESSION RESET actors=", _menu.map_loader.players.actors.size(),
		" map_unloaded=", _menu.map_loader.current_map == null)
	print("SESSION EXIT")
	quit(0)
