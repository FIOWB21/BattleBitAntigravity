extends GutTest

const WORKER: String = "res://tools/lag_worker.gd"
const TIMEOUT_MS: int = 22000
var _directory: String
var _port: int
var _pids: Array[int] = []


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_directory = "res://.godot/lag_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(socket.bind(0, "127.0.0.1"), OK)
	_port = socket.get_local_port()
	socket.close()


func after_each() -> void:
	for suffix: String in ["done", "exit", "client_stop"]:
		FileAccess.open(_directory.path_join(suffix), FileAccess.WRITE).close()
	for pid: int in _pids:
		await _wait_exit(pid)
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()


func test_visible_transverse_player_is_hit_with_150ms_rtt() -> void:
	var result: Dictionary = await _exercise("normal")
	assert_gte(int(result.get("shots", 0)), 6)
	assert_eq(int(result.get("hits", 0)), int(result.get("shots", -1)))
	assert_lt(float(result.get("health", 10000.0)), 10000.0)
	assert_gte(int(result.get("min_age", 0)), 8)
	assert_lte(int(result.get("max_age", 100)), 15)
	assert_true(bool(result.get("restored", false)))


func test_same_visible_aim_misses_when_compensation_is_disabled() -> void:
	var result: Dictionary = await _exercise("disabled")
	assert_gte(int(result.get("shots", 0)), 6)
	assert_eq(int(result.get("hits", -1)), 0)
	assert_almost_eq(float(result.get("health", 0.0)), 10000.0, 0.001)


func test_forged_ancient_view_tick_is_clamped_to_250ms_at_trace() -> void:
	var result: Dictionary = await _exercise("forged")
	assert_gte(int(result.get("shots", 0)), 6)
	assert_eq(int(result.get("min_age", 0)), 15)
	assert_eq(int(result.get("max_age", 0)), 15)
	assert_true(bool(result.get("restored", false)))


func _exercise(mode: String) -> Dictionary:
	var server: String = _directory.path_join("server.log")
	var client: String = _directory.path_join("client.log")
	var server_pid: int = _launch(server, "server", mode)
	await _wait_text(server, "LAG READY")
	var client_pid: int = _launch(client, "client", mode)
	await _wait_text(client, "LAG CLIENT DONE")
	await _wait_text(server, "LAG SERVER DONE")
	var authoritative: Dictionary = _record(server, "LAG SERVER ")
	var replica: Dictionary = _record(client, "LAG CLIENT ")
	assert_almost_eq(float(replica.get("ping", 0.0)), 150.0, 20.0)
	assert_gte(int(replica.get("samples", 0)), 150)
	assert_almost_eq(float(replica.get("server_estimate", 0.0)) - float(replica.get("view_tick", 0)),
		6.5, 0.6, "View tick subtracts 100 ms, independently of predicted input tick")
	FileAccess.open(_directory.path_join("client_stop"), FileAccess.WRITE).close()
	await _wait_exit(client_pid)
	FileAccess.open(_directory.path_join("exit"), FileAccess.WRITE).close()
	await _wait_exit(server_pid)
	for path: String in [server, client]:
		assert_has(_read(path), "LAG CLEANUP actors=0 history=0")
		for forbidden: String in ["SCRIPT ERROR", "ERROR:", "WARNING:", "timeout"]:
			assert_false(_read(path).contains(forbidden), _read(path))
	print("LAG METRIC mode=", mode, " server=", JSON.stringify(authoritative),
		" client=", JSON.stringify(replica), " logs=", _directory)
	return authoritative


func _launch(log_path: String, role: String, mode: String) -> int:
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(log_path), "-s", WORKER, "--",
		"--port=" + str(_port), "--role=" + role, "--mode=" + mode, "--directory=" + _directory]
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
	assert_false(OS.is_process_running(pid), "Lag worker exits normally")


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
