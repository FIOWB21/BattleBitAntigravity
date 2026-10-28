extends GutTest

const WORKER: String = "res://tools/handshake_worker.gd"
const WAIT_SECONDS: float = 8.0
var _directory: String
var _pids: Array[int] = []
var _port: int
var _server_log: String
var _stop_file: String


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_directory = "res://.godot/handshake_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	_port = _available_port()
	_server_log = _directory.path_join("server.log")
	_stop_file = _directory.path_join("stop")


func after_each() -> void:
	var marker: FileAccess = FileAccess.open(_stop_file, FileAccess.WRITE)
	if marker != null:
		marker.close()
	for pid: int in _pids:
		await _wait_exit(pid)
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()


func test_real_processes_accept_client_and_reject_wrong_protocol() -> void:
	await _start_server()
	var good: String = _directory.path_join("good.log")
	var good_pid: int = _launch(good, ["--nickname=ClientOne"])
	assert_true(await _wait_for(good, "WORKER CONNECTED"))
	await _wait_exit(good_pid)
	assert_true(await _wait_for(_server_log, "WORKER LEFT"))
	var bad: String = _directory.path_join("bad_version.log")
	var bad_pid: int = _launch(bad, ["--mode=custom", "--version=1", "--nickname=OtherClient"])
	assert_true(await _wait_for(bad, "WORKER REJECTED reason=protocol_mismatch"))
	await _wait_exit(bad_pid)
	var server: String = _read(_server_log)
	assert_eq(server.count("WORKER ACCEPT"), 1, "Duplicate hello never admits twice")
	assert_has(server, "reason=protocol_mismatch")
	assert_false(server.contains("nickname=OtherClient"))
	_assert_clean([good, bad, _server_log])


func test_real_processes_check_password_nickname_and_uniqueness() -> void:
	await _start_server("secret")
	var owner: String = _directory.path_join("owner.log")
	_launch(owner, ["--nickname=Owner", "--password=secret", "--hold=4.0"])
	assert_true(await _wait_for(owner, "WORKER CONNECTED"))
	await _expect_rejection("wrong_password", ["--nickname=Other", "--password=wrong"])
	await _expect_rejection("nickname_in_use", ["--nickname=OWNER", "--password=secret"])
	await _expect_rejection("invalid_nickname", ["--mode=custom", "--nickname=bad name", "--password=secret"])
	assert_eq(_read(_server_log).count("WORKER ACCEPT"), 1)
	assert_false(_read(_server_log).contains("secret"), "Password never appears in server logs")
	_assert_clean([owner, _server_log])


func test_silent_client_times_out_without_join_or_left_events() -> void:
	await _start_server()
	await _expect_rejection("hello_timeout", ["--mode=silent"])
	var server: String = _read(_server_log)
	assert_false(server.contains("WORKER ACCEPT"))
	assert_false(server.contains("WORKER LEFT"))
	_assert_clean([_server_log])


func test_server_shutdown_is_reported_and_released_nickname_can_rejoin() -> void:
	await _start_server()
	var first: String = _directory.path_join("first.log")
	var pid: int = _launch(first, ["--nickname=Again"])
	assert_true(await _wait_for(first, "WORKER CONNECTED"))
	await _wait_exit(pid)
	assert_true(await _wait_for(_server_log, "WORKER LEFT"))
	var second: String = _directory.path_join("second.log")
	_launch(second, ["--nickname=Again", "--hold=6.0"])
	assert_true(await _wait_for(second, "WORKER CONNECTED"))
	var marker: FileAccess = FileAccess.open(_stop_file, FileAccess.WRITE)
	marker.close()
	assert_true(await _wait_for(second, "WORKER REJECTED reason=server_disconnected"))
	assert_eq(_read(_server_log).count("WORKER ACCEPT"), 2)
	_assert_clean([first, second, _server_log])


func _start_server(password: String = "") -> void:
	_launch(_server_log, ["--role=server", "--password=" + password, "--stop-file=" + _stop_file])
	assert_true(await _wait_for(_server_log, "WORKER READY"), _read(_server_log))


func _launch(log_path: String, options: PackedStringArray) -> int:
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(log_path), "-s", WORKER, "--", "--port=" + str(_port)]
	args.append_array(options)
	var pid: int = OS.create_process(OS.get_executable_path(), args)
	assert_gt(pid, 0, "OS.create_process starts a separate Godot process")
	if pid > 0:
		_pids.append(pid)
	return pid


func _expect_rejection(reason: String, options: PackedStringArray) -> void:
	var path: String = _directory.path_join(reason + ".log")
	var pid: int = _launch(path, options)
	assert_true(await _wait_for(path, "WORKER REJECTED reason=" + reason), _read(path))
	await _wait_exit(pid)
	assert_false(_read(path).contains("WORKER CONNECTED"))
	_assert_clean([path])


func _wait_for(path: String, marker: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _read(path).contains(marker):
			return true
		await get_tree().create_timer(0.03).timeout
	return false


func _wait_exit(pid: int) -> void:
	var deadline: int = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.03).timeout


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _assert_clean(paths: PackedStringArray) -> void:
	for path: String in paths:
		var log_text: String = _read(path)
		assert_false(log_text.contains("SCRIPT ERROR"), path)
		assert_false(log_text.contains("ERROR:"), path)
		assert_false(log_text.contains("WARNING:"), path)


func _available_port() -> int:
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	var result: Error = socket.bind(0, "127.0.0.1")
	assert_eq(result, OK)
	var port: int = socket.get_local_port()
	socket.close()
	return port
