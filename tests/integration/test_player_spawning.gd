extends GutTest

const WORKER: String = "res://tools/spawn_worker.gd"
const WAIT_SECONDS: float = 12.0
var _directory: String
var _stop_file: String
var _port: int
var _pids: Array[int] = []


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_directory = "res://.godot/spawn_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
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


func test_listen_host_and_two_clients_spawn_late_join_remove_and_reconnect() -> void:
	var host: String = _directory.path_join("host.log")
	_launch(host, ["--role=host", "--stop-file=" + _stop_file])
	await _wait_count(host, 1)
	var first: String = _directory.path_join("first.log")
	var first_pid: int = _launch(first, ["--nickname=First", "--hold=8"])
	await _wait_count(first, 2)
	var second: String = _directory.path_join("second.log")
	var second_pid: int = _launch(second, ["--nickname=Second", "--hold=1.5"])
	await _wait_count(second, 3)
	var host_three: Dictionary = await _wait_count(host, 3)
	var first_three: Dictionary = await _wait_count(first, 3)
	_assert_roles(host, 3, true)
	_assert_roles(first, 3, false)
	_assert_roles(second, 3, false)
	_assert_same_positions([host, first, second], 3)
	await _wait_exit(second_pid)
	await _wait_count(host, 2, int(host_three.get("time", 0)) + 1)
	await _wait_count(first, 2, int(first_three.get("time", 0)) + 1)
	var rejoined: String = _directory.path_join("rejoined.log")
	var rejoined_pid: int = _launch(rejoined, ["--nickname=Second", "--hold=1"])
	await _wait_count(rejoined, 3)
	_assert_roles(rejoined, 3, false)
	await _wait_exit(rejoined_pid)
	await _wait_exit(first_pid)
	_assert_reset([first, second, rejoined])
	_assert_clean([host, first, second, rejoined])


func test_dedicated_server_has_no_local_player_and_clients_have_one_capsule_each() -> void:
	var server: String = _directory.path_join("dedicated.log")
	_launch(server, ["--role=dedicated", "--stop-file=" + _stop_file])
	await _wait_ready(server)
	var first: String = _directory.path_join("first.log")
	var second: String = _directory.path_join("second.log")
	var first_pid: int = _launch(first, ["--nickname=First", "--hold=2.5"])
	await _wait_count(first, 1)
	var second_pid: int = _launch(second, ["--nickname=Second", "--hold=1"])
	await _wait_count(second, 2)
	await _wait_count(first, 2)
	_assert_roles(first, 2, false)
	_assert_roles(second, 2, false)
	var sample: Dictionary = await _wait_count(server, 2)
	for actor: Dictionary in sample.get("actors", []):
		assert_false(bool(actor["local"]))
		assert_false(bool(actor["camera"]))
		assert_false(bool(actor["hud"]))
		assert_true(bool(actor["sim"]))
	_assert_same_positions([server, first, second], 2)
	await _wait_exit(second_pid)
	await _wait_exit(first_pid)
	_assert_reset([first, second])
	_assert_clean([server, first, second])


func test_admitted_client_without_matching_map_ready_never_receives_players() -> void:
	var host: String = _directory.path_join("host.log")
	_launch(host, ["--role=host", "--stop-file=" + _stop_file])
	await _wait_count(host, 1)
	var stalled: String = _directory.path_join("stalled.log")
	var pid: int = _launch(stalled, ["--nickname=Stalled", "--skip-ready=true", "--hold=1"])
	await _wait_exit(pid)
	assert_has(_read(stalled), "NET CONNECTED")
	for sample: Dictionary in _samples(stalled):
		assert_eq((sample["actors"] as Array).size(), 0)
	for sample: Dictionary in _samples(host):
		assert_lte((sample["actors"] as Array).size(), 1)
	_assert_clean([host, stalled])


func test_wrong_map_confirmation_and_missing_client_map_do_not_spawn() -> void:
	var host: String = _directory.path_join("host.log")
	_launch(host, ["--role=host", "--stop-file=" + _stop_file])
	await _wait_count(host, 1)
	var wrong: String = _directory.path_join("wrong.log")
	var wrong_pid: int = _launch(wrong, ["--nickname=Wrong", "--wrong-ready=true", "--hold=0.8"])
	await _wait_exit(wrong_pid)
	var missing: String = _directory.path_join("missing.log")
	var missing_pid: int = _launch(missing, ["--nickname=Missing", "--missing-map=true", "--hold=0.8"])
	await _wait_exit(missing_pid)
	assert_has(_read(missing), "NET FAILED reason=map_load_failed")
	for path: String in [wrong, missing]:
		for sample: Dictionary in _samples(path):
			assert_eq((sample["actors"] as Array).size(), 0)
	for sample: Dictionary in _samples(host):
		assert_lte((sample["actors"] as Array).size(), 1)
	_assert_clean([host, wrong, missing])


func _assert_roles(path: String, count: int, server: bool) -> void:
	var sample: Dictionary = _find_count(path, count)
	assert_false(sample.is_empty(), _read(path))
	var local_count: int = 0
	for actor: Dictionary in sample.get("actors", []):
		var local: bool = int(actor["id"]) == int(sample["self"])
		assert_eq(bool(actor["local"]), local)
		assert_eq(bool(actor["camera"]), local)
		assert_eq(bool(actor["hud"]), local)
		assert_eq(bool(actor["capsule"]), not local)
		assert_eq(bool(actor["sim"]), server)
		assert_eq(int(actor["state_authority"]), 1)
		assert_eq(int(actor["input_authority"]), int(actor["id"]))
		assert_eq(float(actor["health"]), 100.0)
		local_count += 1 if local else 0
	assert_eq(local_count, 1)
	assert_eq(sample.get("map"), "testbed", "Map comes from the handshake")


func _assert_same_positions(paths: PackedStringArray, count: int) -> void:
	var expected: Dictionary = {}
	for path: String in paths:
		var sample: Dictionary = _find_count(path, count)
		var poses: Dictionary = {}
		for actor: Dictionary in sample.get("actors", []):
			var position: Vector3 = str_to_var(String(actor["position"])) as Vector3
			poses[int(actor["id"])] = Vector2(position.x, position.z)
			# Server gravity now settles Y; clients retain the spawn height until snapshots.
			assert_gte(position.y, -0.001)
			assert_lte(position.y, 0.101)
		if expected.is_empty():
			expected = poses
		assert_eq(poses, expected, "Identical horizontal spawn positions on all machines")


func _wait_count(path: String, count: int, after_ms: int = 0) -> Dictionary:
	var deadline: int = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	var result: Dictionary = _find_count(path, count, after_ms)
	while result.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.03).timeout
		result = _find_count(path, count, after_ms)
	assert_false(result.is_empty(), "Expected %d players: %s" % [count, _read(path)])
	return result


func _find_count(path: String, count: int, after_ms: int = 0) -> Dictionary:
	for sample: Dictionary in _samples(path):
		if (sample["actors"] as Array).size() == count and int(sample["time"]) >= after_ms:
			return sample
	return {}


func _samples(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for line: String in _read(path).split("\n"):
		if line.begins_with("SPAWN SAMPLE "):
			var value: Variant = JSON.parse_string(line.trim_prefix("SPAWN SAMPLE "))
			if value is Dictionary:
				result.append(value as Dictionary)
	return result


func _wait_ready(path: String) -> void:
	var deadline: int = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while not _read(path).contains("SPAWN READY") and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.03).timeout
	assert_has(_read(path), "SPAWN READY")


func _launch(path: String, options: PackedStringArray) -> int:
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(path), "-s", WORKER, "--", "--port=" + str(_port)]
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


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _assert_reset(paths: PackedStringArray) -> void:
	for path: String in paths:
		assert_has(_read(path), 'SPAWN RESET {"actors":0,"map_unloaded":true,"menu":true}')


func _assert_clean(paths: PackedStringArray) -> void:
	for path: String in paths:
		for forbidden: String in ["SCRIPT ERROR", "ERROR:", "WARNING:"]:
			assert_false(_read(path).contains(forbidden), path)
