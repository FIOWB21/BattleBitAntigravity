extends GutTest

const WORKER: String = "res://tools/weapon_presentation_worker.gd"
const TIMEOUT_MS: int = 22000
var _directory: String
var _port: int
var _pids: Array[int] = []


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_directory = "res://.godot/weapon_public_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(socket.bind(0, "127.0.0.1"), OK)
	_port = socket.get_local_port()
	socket.close()


func after_each() -> void:
	for index: int in range(_pids.size() - 1, -1, -1):
		FileAccess.open(_directory.path_join("stop%d" % index), FileAccess.WRITE).close()
		await _wait_exit(_pids[index])
		if OS.is_process_running(_pids[index]):
			OS.kill(_pids[index])
	_pids.clear()


func test_listen_host_sees_remote_weapon_reload_crouch_aim_and_one_event_per_shot() -> void:
	await _exercise(false)


func test_dedicated_routes_public_events_and_keeps_ammo_private_including_late_join() -> void:
	await _exercise(true)


func _exercise(dedicated: bool) -> void:
	var role: String = "dedicated" if dedicated else "listen"
	_launch("server", ["--role=" + role, "--nick=Observer"])
	await _wait_text("server", "WEAPON READY")
	_launch("shooter", ["--nick=Shooter"])
	if dedicated:
		_launch("observer", ["--nick=Observer"])
	await _wait_text("server", "WEAPON RELOAD")
	_launch("late", ["--nick=Late"])
	await _wait_text("server", "WEAPON SERVER DONE")
	var logs: Array[String] = ["shooter", "late", "observer" if dedicated else "server"]
	for label: String in logs:
		await _wait_text(label, "WEAPON CLIENT DONE")
		_assert_result(_result(label), label == "server")
	for index: int in range(_pids.size() - 1, -1, -1):
		FileAccess.open(_directory.path_join("stop%d" % index), FileAccess.WRITE).close()
		await _wait_exit(_pids[index])
	if dedicated:
		logs.append("server")
	for label: String in logs:
		var log_text: String = _read(label)
		assert_has(log_text, "WEAPON CLEANUP actors=0")
		for forbidden: String in ["SCRIPT ERROR", "ERROR:", "WARNING:", "timeout"]:
			assert_false(log_text.contains(forbidden), log_text)
	print("WEAPON METRIC dedicated=", dedicated, " logs=", _directory)


func _assert_result(result: Dictionary, server: bool) -> void:
	assert_eq(result.get("actors", 0), 3)
	if result.get("nickname", "") == "Shooter":
		assert_eq(result.get("events", -1), 0, "Owner does not receive its predicted effects again")
		assert_gt(result.get("ammo_syncs", 0), 0)
		assert_eq(result.get("own_magazine", -1), 2)
		assert_eq(result.get("own_reserve", -1), 17)
		assert_eq(result.get("hud_magazine", -1), 2)
		return
	assert_eq(result.get("events", -1), 1 if result.get("nickname", "") == "Late" else 4)
	assert_eq(result.get("ammo_syncs", -1), 0)
	var seen: Dictionary = result.get("seen", {})
	for state: String in ["rifle", "pistol", "reload", "crouch", "aim", "pitch"]:
		assert_true(seen.get(state, false), state + " must be presented from the server")
	if not server:
		assert_true(result.get("foreign_ammo_unchanged", false))
		assert_false(seen.get("foreign_state", true), "Remote Weapon is never simulated for presentation")


func _launch(label: String, options: PackedStringArray) -> void:
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(_directory.path_join(label + ".log")),
		"-s", WORKER, "--", "--port=" + str(_port),
		"--report=" + _directory.path_join("report"),
		"--stop=" + _directory.path_join("stop%d" % _pids.size())]
	args.append_array(options)
	var pid: int = OS.create_process(OS.get_executable_path(), args)
	assert_gt(pid, 0)
	if pid > 0:
		_pids.append(pid)


func _result(label: String) -> Dictionary:
	for line: String in _read(label).split("\n"):
		if line.begins_with("WEAPON RESULT "):
			return JSON.parse_string(line.trim_prefix("WEAPON RESULT ")) as Dictionary
	assert_true(false, _read(label))
	return {}


func _wait_text(label: String, expected: String) -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while not _read(label).contains(expected) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.04).timeout
	assert_has(_read(label), expected, _read(label))


func _wait_exit(pid: int) -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.04).timeout
	assert_false(OS.is_process_running(pid), "Weapon worker exits normally")


func _read(label: String) -> String:
	var path: String = _directory.path_join(label + ".log")
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
