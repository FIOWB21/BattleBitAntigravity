extends GutTest

const WORKER: String = "res://tools/prediction_worker.gd"
const TIMEOUT_MS: int = 22000
var _directory: String
var _port: int
var _pids: Array[int] = []


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_directory = "res://.godot/prediction_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(socket.bind(0, "127.0.0.1"), OK)
	_port = socket.get_local_port()
	socket.close()


func after_each() -> void:
	FileAccess.open(_directory.path_join("client.stop"), FileAccess.WRITE).close()
	FileAccess.open(_directory.path_join("server.stop"), FileAccess.WRITE).close()
	for pid: int in _pids:
		await _wait_exit(pid)
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()


func test_real_enet_120ms_two_percent_loss_predicts_and_runs_without_rubberband() -> void:
	await _exercise("120", "2")


func test_real_enet_loopback_prediction_keeps_server_authority() -> void:
	await _exercise("0", "0")


func test_real_server_correction_replays_owner_input_and_smooths_camera() -> void:
	await _exercise("120", "2", true)


func _exercise(ping: String, loss: String, shift: bool = false) -> void:
	var server: String = _directory.path_join("server.log")
	var client: String = _directory.path_join("client.log")
	var shift_args: PackedStringArray = []
	if shift:
		shift_args.append("--shift-file=" + _directory.path_join("shift"))
	var server_args: PackedStringArray = ["--role=dedicated"]
	server_args.append_array(shift_args)
	var server_pid: int = _launch(server, server_args)
	await _wait_text(server, "PRED READY")
	var client_args: PackedStringArray = ["--ping=" + ping, "--loss=" + loss]
	client_args.append_array(shift_args)
	var client_pid: int = _launch(client, client_args)
	await _wait_text(client, "PRED DONE")
	FileAccess.open(_directory.path_join("client.stop"), FileAccess.WRITE).close()
	await _wait_exit(client_pid)
	await get_tree().create_timer(0.1).timeout
	FileAccess.open(_directory.path_join("server.stop"), FileAccess.WRITE).close()
	await _wait_exit(server_pid)
	_assert_result(client, ping, shift)
	for path: String in [client, server]:
		_assert_clean(path)
	if shift:
		assert_has(_read(server), "PRED SHIFT 0.5")


func _assert_result(client: String, ping: String, shift: bool) -> void:
	var response: Dictionary = _record(client, "PRED RESPONSE ")
	assert_gt(float(response.get("distance", 0.0)), 0.0, "Local movement starts on the first tick")
	var result: Dictionary = _record(client, "PRED RESULT ")
	assert_gt(float(result.get("distance", 0.0)), 20.0)
	assert_eq(int(result.get("server_steps", -1)), 0)
	assert_eq(int(result.get("teleports", -1)), 0)
	assert_eq(int(result.get("history_misses", -1)), 0)
	assert_eq(int(result.get("backward_camera_steps", -1)), 0,
		"Reconciliation corrects the body immediately; presentation must keep moving forward")
	assert_lt(float(result.get("max_step", 100.0)), 0.8 if shift else 0.25)
	assert_lt(float(result.get("max_camera_step", 100.0)), 0.25)
	assert_lt(int(result.get("reconciliations", 1000)), 20, "Fewer than 3.3 corrections/second on a six-second route")
	assert_true(bool(result.get("ammo_unchanged", false)))
	assert_lt(float(result.get("offset", 1.0)), 0.02)
	if ping == "120":
		assert_gt(float(result.get("ping", 0.0)), 110.0)
		assert_gt(int(result.get("input_drops", 0)) + int(result.get("snapshot_drops", 0)), 0)
	if shift:
		assert_gt(int(result.get("reconciliations", 0)), 0)
		assert_gt(float(result.get("distance", 0.0)), 24.4)
	print("PRED METRIC ", client, " ", JSON.stringify(result))


func _launch(path: String, options: PackedStringArray) -> int:
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(path), "-s", WORKER, "--",
		"--port=" + str(_port), "--stop-file=" + _directory.path_join("server.stop"),
		"--client-stop=" + _directory.path_join("client.stop")]
	args.append_array(options)
	var pid: int = OS.create_process(OS.get_executable_path(), args)
	assert_gt(pid, 0)
	if pid > 0:
		_pids.append(pid)
	return pid


func _assert_clean(path: String) -> void:
	assert_has(_read(path), "PRED CLEANUP actors=0")
	for forbidden: String in ["SCRIPT ERROR", "ERROR:", "WARNING:", "timeout"]:
		assert_false(_read(path).contains(forbidden), _read(path))


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
	assert_false(OS.is_process_running(pid), "Prediction worker exits normally")


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
