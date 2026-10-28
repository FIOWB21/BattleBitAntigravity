extends GutTest

const WORKER: String = "res://tools/input_worker.gd"
const TIMEOUT_MS: int = 15000
var _directory: String
var _stop: String
var _port: int
var _pids: Array[int] = []


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_directory = "res://.godot/input_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	_stop = _directory.path_join("stop")
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(socket.bind(0, "127.0.0.1"), OK)
	_port = socket.get_local_port()
	socket.close()


func after_each() -> void:
	FileAccess.open(_stop, FileAccess.WRITE).close()
	for pid: int in _pids:
		await _wait_exit(pid)
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()


func test_dedicated_server_receives_real_input_and_matches_local_replay() -> void:
	await _exercise("dedicated")


func test_listen_server_rejects_other_owner_and_invalid_wire_inputs() -> void:
	await _exercise("host")


func _exercise(role: String) -> void:
	var server: String = _directory.path_join("server.log")
	var server_pid: int = _launch(server, ["--role=" + role, "--stop-file=" + _stop])
	await _wait_text(server, "INPUT READY")
	var client: String = _directory.path_join("client.log")
	var client_pid: int = _launch(client, ["--attack=true"])
	await _wait_exit(client_pid)
	FileAccess.open(_stop, FileAccess.WRITE).close()
	await _wait_exit(server_pid)
	var steps: Array[Dictionary] = _records(server, "INPUT STEP ")
	assert_false(steps.is_empty(), _read(server))
	_assert_steps(steps, role == "host")
	var replay: Array[Dictionary] = _records(server, "INPUT REPLAY ")
	assert_eq(replay.size(), 1)
	if not replay.is_empty():
		assert_gt(int(replay[0]["ticks"]), 100)
		assert_lt(float(replay[0]["max_error"]), 0.00001)
	assert_has(_read(client), "INPUT ATTACK future diagonal other_owner")
	assert_has(_read(client), '"simulated":0')
	assert_has(_read(client), '"unchanged":false')
	for path: String in [server, client]:
		assert_has(_read(path), "INPUT CLEANUP actors=0")
		for forbidden: String in ["SCRIPT ERROR", "ERROR:", "WARNING:", "timeout"]:
			assert_false(_read(path).contains(forbidden), _read(path))


func _assert_steps(steps: Array[Dictionary], has_host: bool) -> void:
	var moved: int = 0
	var repeats: Dictionary[int, bool] = {}
	var positions: Array[Vector3] = []
	var last_tick: int = -1
	for sample: Dictionary in steps:
		if has_host and int(sample["id"]) == 1:
			assert_eq(str_to_var(String(sample["move"])), Vector2.ZERO, "Spoof cannot move the host")
			continue
		var move: Vector2 = str_to_var(String(sample["move"])) as Vector2
		assert_gt(int(sample["tick"]), last_tick, "At most one simulation per server tick")
		last_tick = int(sample["tick"])
		if move != Vector2.ZERO:
			assert_eq(move, Vector2.RIGHT, "Diagonal/future attacks never enter simulation")
			moved += 1
			positions.append(str_to_var(String(sample["position"])) as Vector3)
		repeats[int(sample["repeat"])] = true
	assert_gt(moved, 0, "Unreliable delivery produces authoritative movement")
	if positions.size() > 1:
		assert_gt(positions.back().x - positions.front().x, 1.5)
	for repeat: int in range(1, 7):
		assert_has(repeats, repeat, "Five repeats followed by neutral input")


func _launch(path: String, options: PackedStringArray) -> int:
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(path), "-s", WORKER, "--", "--port=" + str(_port)]
	args.append_array(options)
	var pid: int = OS.create_process(OS.get_executable_path(), args)
	assert_gt(pid, 0)
	if pid > 0:
		_pids.append(pid)
	return pid


func _wait_text(path: String, expected: String) -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while not _read(path).contains(expected) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.03).timeout
	assert_has(_read(path), expected)


func _wait_exit(pid: int) -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.03).timeout
	assert_false(OS.is_process_running(pid), "Input worker exits normally")


func _records(path: String, prefix: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for line: String in _read(path).split("\n"):
		if line.begins_with(prefix):
			result.append(JSON.parse_string(line.trim_prefix(prefix)) as Dictionary)
	return result


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
