extends GutTest

const WORKER: String = "res://tools/snapshot_worker.gd"
const TIMEOUT_MS: int = 20000
var _directory: String
var _stop: String
var _pause: String
var _server_stop: String
var _port: int
var _pids: Array[int] = []


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_directory = "res://.godot/snapshots_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	_stop = _directory.path_join("stop")
	_pause = _directory.path_join("pause")
	_server_stop = _directory.path_join("server_stop")
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(socket.bind(0, "127.0.0.1"), OK)
	_port = socket.get_local_port()
	socket.close()


func after_each() -> void:
	FileAccess.open(_stop, FileAccess.WRITE).close()
	FileAccess.open(_server_stop, FileAccess.WRITE).close()
	for file: String in DirAccess.get_files_at(_directory):
		if file.begins_with("client_") and file.ends_with(".log"):
			FileAccess.open(_directory.path_join(file + ".stop"), FileAccess.WRITE).close()
	for pid: int in _pids:
		await _wait_exit(pid)
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()


func test_eight_players_receive_quantized_state_and_measured_traffic_below_budget() -> void:
	await _exercise("dedicated", 8)


func test_listen_host_also_buffers_remote_players_and_acknowledges_owners() -> void:
	await _exercise("host", 2)


func _exercise(role: String, clients: int) -> void:
	var total: int = clients + (1 if role == "host" else 0)
	var server: String = _directory.path_join("server.log")
	var server_pid: int = _launch(server, ["--role=" + role, "--players=" + str(total), "--stop-file=" + _server_stop])
	await _wait_text(server, "SNAP READY")
	var paths: Array[String] = []
	var clients_pids: Array[int] = []
	for index: int in range(clients):
		var path: String = _directory.path_join("client_%d.log" % index)
		paths.append(path)
		clients_pids.append(_launch(path, ["--nickname=Snapshot%d" % index,
			"--players=" + str(total), "--stop-file=" + path + ".stop"]))
		if index == clients - 2:
			await get_tree().create_timer(0.3).timeout
	for path: String in paths:
		await _wait_text(path, "SNAP MEASURE ")
	await _finish_workers(paths, clients_pids, server_pid)
	_assert_cadence(server)
	var states: Dictionary[String, Dictionary] = _server_states(server)
	assert_false(states.is_empty(), _read(server))
	for path: String in paths:
		_assert_client(path, total, states)
		_assert_clean(path)
	_assert_clean(server)


func _finish_workers(paths: Array[String], pids: Array[int], server_pid: int) -> void:
	FileAccess.open(_pause, FileAccess.WRITE).close()
	for path: String in paths:
		await _wait_text(path, "SNAP DONE")
	# Keep the server alive to process each ENet departure before closing the next socket.
	for index: int in range(paths.size()):
		FileAccess.open(paths[index] + ".stop", FileAccess.WRITE).close()
		await _wait_exit(pids[index])
		await get_tree().create_timer(0.1).timeout
	FileAccess.open(_server_stop, FileAccess.WRITE).close()
	await _wait_exit(server_pid)


func _assert_client(path: String, total: int, states: Dictionary[String, Dictionary]) -> void:
	var measures: Array[Dictionary] = _records(path, "SNAP MEASURE ")
	assert_eq(measures.size(), 1, _read(path))
	if measures.is_empty():
		return
	var measurement: Dictionary = measures[0]
	assert_eq(int(measurement["players"]), total)
	assert_true(bool(measurement["local_unchanged"]))
	assert_eq(int(measurement["client_steps"]), 0)
	assert_gt(int(measurement["ack"]), 0)
	var rate: float = float(measurement["snapshots"]) / float(measurement["seconds"])
	assert_lte(rate, 31.5, "Unreliable delivery may drop snapshots; sender cadence is checked separately")
	assert_gt(int(measurement["snapshots"]), 30)
	assert_lt(float(measurement["ipv4_bytes_per_second"]), 20000.0)
	assert_gt(float(measurement["udp_payload"]), int(measurement["snapshot_bytes"]))
	assert_gt(float(measurement["datagrams"]), 0.0)
	assert_has(_read(path), "SNAP FREEZE true")
	assert_has(_read(path), 'SNAP CLEANUP {"actors":0,"bytes":0,"tick":0}')
	var samples: Array[Dictionary] = _records(path, "SNAP CLIENT ")
	assert_gt(samples.size(), total * 10)
	var peers: Dictionary[int, bool] = {}
	var matched: int = 0
	for index: int in range(0, samples.size(), 5):
		var sample: Dictionary = samples[index]
		peers[int(sample["id"])] = true
		var key: String = str(sample["tick"]) + ":" + str(sample["id"])
		if states.has(key):
			_assert_state(sample, states[key])
			var owner_key: String = str(sample["tick"]) + ":" + str(measurement["self"])
			if states.has(owner_key):
				assert_eq(int(sample["ack"]), int(states[owner_key]["ack"]), "Recipient-specific input acknowledgement")
			matched += 1
	assert_gt(matched, 10)
	# Sampling stride is coprime with both tested remote-player counts.
	assert_eq(peers.size(), total - 1)
	print("SNAP TRAFFIC ", path, " ", JSON.stringify(measurement))


func _assert_state(client: Dictionary, server: Dictionary) -> void:
	var client_pos: Vector3 = str_to_var(String(client["pos"])) as Vector3
	var server_pos: Vector3 = str_to_var(String(server["pos"])) as Vector3
	var client_velocity: Vector3 = str_to_var(String(client["velocity"])) as Vector3
	var server_velocity: Vector3 = str_to_var(String(server["velocity"])) as Vector3
	assert_almost_eq(client_pos, server_pos, Vector3(0.0041, 0.0021, 0.0041))
	assert_almost_eq(client_velocity, server_velocity, Vector3.ONE * 0.0011)
	assert_lt(absf(angle_difference(float(server["yaw"]), float(client["yaw"]))), 0.0001)
	assert_almost_eq(float(client["pitch"]), float(server["pitch"]), 0.0001)
	assert_eq(int(client["flags"]) & PlayerSnapshot.STANCE_MASK, int(server["stance"]))
	assert_gt(int(client["weapon"]), 0)


func _server_states(path: String) -> Dictionary[String, Dictionary]:
	var result: Dictionary[String, Dictionary] = {}
	for sample: Dictionary in _records(path, "SNAP SERVER "):
		assert_eq(int(sample["tick"]) % 2, 0)
		result[str(sample["tick"]) + ":" + str(sample["id"])] = sample
	return result


func _assert_cadence(path: String) -> void:
	var cadence: Array[Dictionary] = _records(path, "SNAP CADENCE ")
	assert_eq(cadence.size(), 1)
	if cadence.is_empty():
		return
	assert_eq(int(cadence[0]["errors"]), 0, "Server sends every two simulation ticks")
	assert_gt(int(cadence[0]["frames"]), 120)
	assert_eq(int(cadence[0]["last"]) - int(cadence[0]["first"]), (int(cadence[0]["frames"]) - 1) * 2)


func _launch(path: String, options: PackedStringArray) -> int:
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(path), "-s", WORKER, "--",
		"--port=" + str(_port), "--stop-file=" + _stop, "--pause-file=" + _pause]
	args.append_array(options)
	var pid: int = OS.create_process(OS.get_executable_path(), args)
	assert_gt(pid, 0)
	if pid > 0:
		_pids.append(pid)
	return pid


func _wait_text(path: String, expected: String) -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while not _read(path).contains(expected) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.04).timeout
	assert_has(_read(path), expected, path)


func _wait_exit(pid: int) -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.04).timeout
	assert_false(OS.is_process_running(pid), "Snapshot worker exits normally")


func _records(path: String, prefix: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for line: String in _read(path).split("\n"):
		if line.begins_with(prefix):
			result.append(JSON.parse_string(line.trim_prefix(prefix)) as Dictionary)
	return result


func _assert_clean(path: String) -> void:
	for forbidden: String in ["SCRIPT ERROR", "ERROR:", "WARNING:", "timeout"]:
		assert_false(_read(path).contains(forbidden), path)


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
