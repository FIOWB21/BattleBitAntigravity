extends GutTest

const WORKER: String = "res://tools/fire_worker.gd"
const TIMEOUT_MS: int = 22000
var _directory: String
var _port: int
var _pids: Array[int] = []


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_directory = "res://.godot/fire_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(socket.bind(0, "127.0.0.1"), OK)
	_port = socket.get_local_port()
	socket.close()


func after_each() -> void:
	for filename: String in ["client.stop", "server.stop", "server.exit"]:
		FileAccess.open(_directory.path_join(filename), FileAccess.WRITE).close()
	for pid: int in _pids:
		await _wait_exit(pid)
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()


func test_real_enet_normal_client_fires_reloads_and_receives_server_ammo() -> void:
	await _exercise(false)


func test_real_enet_cheating_ammo_cooldown_duplicates_and_future_ticks_give_no_advantage() -> void:
	await _exercise(true)


func test_real_enet_fire_waits_for_server_input_with_120ms_and_two_percent_loss() -> void:
	await _exercise(false, true)


func _exercise(cheat: bool, delayed: bool = false) -> void:
	var server: String = _directory.path_join("server.log")
	var client: String = _directory.path_join("client.log")
	var server_pid: int = _launch(server, ["--role=dedicated"])
	await _wait_text(server, "FIRE READY")
	var options: PackedStringArray = ["--cheat=" + str(cheat)]
	if delayed:
		options.append("--ping=120")
	var client_pid: int = _launch(client, options)
	await _wait_text(client, "FIRE CLIENT DONE")
	FileAccess.open(_directory.path_join("server.stop"), FileAccess.WRITE).close()
	await _wait_text(server, "FIRE SERVER DONE")
	var authoritative: Dictionary = _record(server, "FIRE SERVER ")
	var replica: Dictionary = _record(client, "FIRE CLIENT ")
	_assert_results(authoritative, replica, cheat)
	FileAccess.open(_directory.path_join("client.stop"), FileAccess.WRITE).close()
	await _wait_exit(client_pid)
	FileAccess.open(_directory.path_join("server.exit"), FileAccess.WRITE).close()
	await _wait_exit(server_pid)
	for path: String in [server, client]:
		assert_has(_read(path), "FIRE CLEANUP actors=0")
		for forbidden: String in ["SCRIPT ERROR", "ERROR:", "WARNING:", "timeout"]:
			assert_false(_read(path).contains(forbidden), _read(path))
	print("FIRE METRIC cheat=", cheat, " server=", JSON.stringify(authoritative),
		" client=", JSON.stringify(replica), " logs=", _directory)


func _assert_results(server: Dictionary, client: Dictionary, cheat: bool) -> void:
	assert_eq(int(server.get("shots", -1)), 6, "Two server magazines, no extra ammunition")
	assert_eq(int(server.get("events", -1)), 6, "Only server traces create DamageEvent")
	assert_almost_eq(float(server.get("health", 0.0)), 9640.0, 0.01)
	assert_gte(int(server.get("min_gap", 0)), 6, "600 RPM on the server clock")
	assert_false(bool(server.get("wrong_attacker", true)))
	assert_false(bool(server.get("wrong_direction", true)))
	assert_eq(int(server.get("magazine", -1)), 0)
	assert_eq(int(server.get("reserve", -1)), 0)
	assert_eq(int(client.get("magazine", -1)), 0)
	assert_eq(int(client.get("reserve", -1)), 0)
	assert_eq(int(client.get("hud", -1)), 0)
	assert_eq(int(client.get("server_steps", -1)), 0)
	assert_true(bool(client.get("health_unchanged", false)))
	assert_gte(int(client.get("effects", 0)), 6, "Immediate predicted shot cosmetics")
	if cheat:
		assert_gt(int(server.get("rejected", 0)), 100)


func _launch(path: String, options: PackedStringArray) -> int:
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(path), "-s", WORKER, "--",
		"--port=" + str(_port), "--server-stop=" + _directory.path_join("server.stop"),
		"--server-exit=" + _directory.path_join("server.exit"),
		"--client-stop=" + _directory.path_join("client.stop")]
	args.append_array(options)
	var pid: int = OS.create_process(OS.get_executable_path(), args)
	assert_gt(pid, 0)
	if pid > 0:
		_pids.append(pid)
	return pid


func _record(path: String, prefix: String) -> Dictionary:
	for line: String in _read(path).split("\n"):
		if line.begins_with(prefix):
			return JSON.parse_string(line.trim_prefix(prefix)) as Dictionary
	assert_true(false, "Missing " + prefix + " in " + _read(path))
	return {}


func _wait_text(path: String, expected: String) -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while not _read(path).contains(expected) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.04).timeout
	assert_has(_read(path), expected, _read(path))


func _wait_exit(pid: int) -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.04).timeout
	assert_false(OS.is_process_running(pid), "Fire worker exits normally")


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
