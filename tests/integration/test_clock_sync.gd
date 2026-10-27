extends GutTest

const WORKER: String = "res://tools/clock_worker.gd"
const WAIT_SECONDS: float = 10.0
var _directory: String
var _server_log: String
var _stop_file: String
var _port: int
var _pids: Array[int] = []


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_directory = "res://.godot/clock_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	_server_log = _directory.path_join("server.log")
	_stop_file = _directory.path_join("stop")
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(socket.bind(0, "127.0.0.1"), OK)
	_port = socket.get_local_port()
	socket.close()


func after_each() -> void:
	var marker: FileAccess = FileAccess.open(_stop_file, FileAccess.WRITE)
	if marker != null:
		marker.close()
	for pid: int in _pids:
		await _wait_exit(pid)
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()


func test_real_enet_measures_100ms_and_advances_client_ahead_of_actual_server() -> void:
	await _start_server()
	var delayed: String = _directory.path_join("delayed.log")
	var local: String = _directory.path_join("local.log")
	var delayed_pid: int = _launch(delayed, ["--nickname=Delayed", "--delay=100"])
	var local_pid: int = _launch(local, ["--nickname=Local", "--delay=0"])
	await _wait_exit(delayed_pid)
	await _wait_exit(local_pid)
	_assert_client(delayed, 100.0)
	_assert_client(local, 0.0)
	_assert_clean([_server_log, delayed, local])


func test_complete_probe_loss_times_out_then_recovers_without_a_stale_sample() -> void:
	await _start_server()
	var log_path: String = _directory.path_join("loss.log")
	var pid: int = _launch(log_path, ["--loss=100", "--recover=2.5", "--hold=7.0"])
	await _wait_exit(pid)
	assert_has(_read(log_path), "CLOCK RECOVER samples=0 tick=0")
	_assert_client(log_path, 100.0)
	_assert_clean([_server_log, log_path])


func test_probes_keep_half_second_cadence_when_rtt_exceeds_the_interval() -> void:
	await _start_server()
	var log_path: String = _directory.path_join("overlap.log")
	var pid: int = _launch(log_path, ["--delay=600", "--hold=5.5"])
	await _wait_exit(pid)
	_assert_client(log_path, 600.0)
	_assert_clean([_server_log, log_path])


func _assert_client(path: String, expected_ping: float) -> void:
	var samples: Array[Dictionary] = _records(path, "CLOCK SAMPLE ")
	assert_gt(samples.size(), 10, _read(path))
	if samples.is_empty():
		return
	var last: Dictionary = samples.back()
	var actual_server: float = _server_tick_at(float(last["time"]))
	assert_almost_eq(float(last["ping"]), expected_ping, 15.0, "Measured RTT, not requested delay")
	assert_gte(int(last["samples"]), 5)
	assert_gte(int(last["probes"]), 9, "Ping cadence continues independently of replies")
	assert_true(bool(last["overlay_ok"]), "Overlay shows the measured RTT")
	assert_almost_eq(float(last["estimate"]), actual_server, 2.0, "Independent server log")
	assert_almost_eq(float(last["tick"]) - actual_server, float(last["lead"]), 2.0)
	assert_almost_eq(float(last["lead"]), expected_ping / 1000.0 * 60.0 * 0.5 + 2.0, 0.5)
	var previous: int = -1
	for sample: Dictionary in samples:
		assert_true(int(sample["tick"]) >= previous, "Client tick never runs backwards")
		previous = int(sample["tick"])
	var resets: Array[Dictionary] = _records(path, "CLOCK RESET ")
	assert_eq(resets.size(), 1)
	if not resets.is_empty():
		assert_eq(int(resets[0]["tick"]), 0)
		assert_eq(int(resets[0]["samples"]), 0)
		assert_eq(int(resets[0]["nodes"]), 3, "Clock timers are reused")
		assert_almost_eq(float(resets[0]["ping"]), 0.0, 0.0001)
	print("CLOCK ACCEPT ping=%.2fms lead=%.2f actual_lead=%.2f samples=%d" %
		[float(last["ping"]), float(last["lead"]), float(last["tick"]) - actual_server, int(last["samples"])])


func _server_tick_at(wall_time: float) -> float:
	var records: Array[Dictionary] = _records(_server_log, "CLOCK SERVER ")
	assert_false(records.is_empty())
	var nearest: Dictionary = {}
	var distance: float = INF
	for record: Dictionary in records:
		var offset: float = absf(float(record["time"]) - wall_time)
		if offset < distance:
			nearest = record
			distance = offset
	assert_lt(distance, 0.1, "Server and client observed concurrently")
	return float(nearest.get("tick", 0)) + (wall_time - float(nearest.get("time", wall_time))) * 60.0


func _start_server() -> void:
	_launch(_server_log, ["--role=server", "--stop-file=" + _stop_file])
	var deadline: int = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline and not _read(_server_log).contains("CLOCK READY"):
		await get_tree().create_timer(0.03).timeout
	assert_has(_read(_server_log), "CLOCK READY")


func _launch(log_path: String, options: PackedStringArray) -> int:
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(log_path), "-s", WORKER, "--", "--port=" + str(_port)]
	args.append_array(options)
	var pid: int = OS.create_process(OS.get_executable_path(), args)
	assert_gt(pid, 0)
	if pid > 0:
		_pids.append(pid)
	return pid


func _wait_exit(pid: int) -> void:
	var deadline: int = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.03).timeout
	assert_false(OS.is_process_running(pid), "Worker exits normally")


func _records(path: String, prefix: String) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for line: String in _read(path).split("\n"):
		if line.begins_with(prefix):
			var value: Variant = JSON.parse_string(line.trim_prefix(prefix))
			if value is Dictionary:
				records.append(value as Dictionary)
	return records


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _assert_clean(paths: PackedStringArray) -> void:
	for path: String in paths:
		var content: String = _read(path)
		assert_false(content.contains("SCRIPT ERROR"), path)
		assert_false(content.contains("ERROR:"), path)
		assert_false(content.contains("WARNING:"), path)
