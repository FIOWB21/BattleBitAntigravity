extends GutTest

const WORKER: String = "res://tools/disconnect_worker.gd"
const WAIT_SECONDS: float = 18.0
var _directory: String
var _server: String
var _stop: String
var _control: String
var _port: int
var _pids: Array[int] = []


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_directory = "res://.godot/disconnect_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	_server = _directory.path_join("server.log")
	_stop = _directory.path_join("stop")
	_control = _directory.path_join("control")
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(socket.bind(0, "127.0.0.1"), OK)
	_port = socket.get_local_port()
	socket.close()


func after_each() -> void:
	_write(_stop, "stop")
	for pid: int in _pids:
		await _wait_exit(pid)
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()
	for filename: String in DirAccess.get_files_at(_directory):
		if filename.ends_with(".log"):
			var log_text: String = _read(_directory.path_join(filename))
			assert_false(log_text.contains("SCRIPT ERROR"), log_text)
			assert_false(log_text.contains("ERROR:"), log_text)
			assert_false(log_text.contains("WARNING:"), log_text)


func test_vanished_client_times_out_frees_only_slot_and_restores_team_on_reconnect() -> void:
	await _start(["--max=1"])
	var first: String = _directory.path_join("first.log")
	_launch(first, ["--nickname=Again", "--vanish"])
	assert_true(await _wait_for(first, "SESSION BLACKHOLE"), _read(first))
	var dropped_at: int = Time.get_ticks_msec()
	var cleaned: Dictionary = await _wait_state(_server, 0, true)
	var elapsed: float = float(Time.get_ticks_msec() - dropped_at) / 1000.0
	print("DISCONNECT measured silent seconds=", elapsed)
	assert_gte(elapsed, 9.0, "A live idle connection is not disconnected early")
	assert_lte(elapsed, 11.5, "10 seconds plus transport polling tolerance")
	for key: String in ["actors", "ready", "slots", "names", "tracks", "snapshots", "respawns", "pending", "closing"]:
		assert_eq(int(cleaned.get(key, -1)), 0, key + " is released")
	var rejoined: String = _directory.path_join("rejoined.log")
	_launch(rejoined, ["--nickname=AGAIN"])
	var restored: Dictionary = await _wait_state(rejoined, 1)
	assert_has(_read(rejoined), "NET CONNECTED")
	assert_eq((restored.get("teams", {}) as Dictionary).values(), [2.0])
	assert_eq(_read(_server).count("NET ACCEPT"), 2, "The single ENet slot can be reused")


func test_spawned_duplicate_nickname_and_wrong_server_password_are_rejected() -> void:
	await _start(["--password=join_secret"])
	var owner: String = _directory.path_join("owner.log")
	_launch(owner, ["--nickname=Owner", "--password=join_secret"])
	await _wait_state(owner, 1)
	await _rejected("duplicate", "nickname_in_use", ["--nickname=OWNER", "--password=join_secret"])
	await _rejected("password", "wrong_password", ["--nickname=Other", "--password=wrong"])
	assert_eq(_read(_server).count("NET ACCEPT"), 1)
	assert_false(_read(_server).contains("join_secret"))
	assert_false(_read(owner).contains("SESSION REJECTED"))


func test_admin_kick_ban_blacklist_unban_and_rejoin_use_the_server_ip() -> void:
	await _start(["--host"])
	var target: String = _directory.path_join("target.log")
	_launch(target, ["--nickname=KickMe"])
	await _wait_state(target, 2)
	_write(_control, "/kick kickme")
	assert_true(await _wait_for(target, "SESSION REJECTED reason=admin_kick"), _read(target))
	await _wait_state(_server, 1)
	var again: String = _directory.path_join("again.log")
	_launch(again, ["--nickname=KickMe"])
	await _wait_state(again, 2)
	_write(_control, "/ban KickMe")
	assert_true(await _wait_for(again, "SESSION REJECTED reason=ip_banned"), _read(again))
	await _wait_state(_server, 1)
	await _rejected("renamed", "ip_banned", ["--nickname=Different"])
	_write(_control, "/blacklist")
	assert_true(await _wait_for(_server, "Blocked IPs: 127.0.0.1"), _read(_server))
	_write(_control, "/unban 127.0.0.1")
	assert_true(await _wait_for(_server, "SESSION NOTICE IP removed."), _read(_server))
	var allowed: String = _directory.path_join("allowed.log")
	_launch(allowed, ["--nickname=KickMe"])
	var state: Dictionary = await _wait_state(allowed, 2)
	assert_has((state.get("teams", {}) as Dictionary).values(), 2.0)
	assert_eq(_read(_server).count("NET ACCEPT"), 3)


func test_configured_blacklist_rejects_before_admission() -> void:
	await _start(["--blocked"])
	await _rejected("blocked", "ip_banned", ["--nickname=Blocked"])
	assert_eq(_read(_server).count("NET ACCEPT"), 0)
	assert_false(_read(_server).contains("nickname=Blocked"))


func test_gameplay_packets_keep_connection_alive_without_clock_probes() -> void:
	await _start([])
	var client: String = _directory.path_join("traffic.log")
	_launch(client, ["--nickname=Traffic", "--no-probes"])
	assert_true(await _wait_for(client, "SESSION TRAFFIC ALIVE"), _read(client))
	assert_false(_read(client).contains("SESSION REJECTED"))
	assert_false(_read(_server).contains("NET TIMEOUT"))
	var state: Dictionary = await _wait_state(_server, 1)
	assert_eq(int(state.get("names", -1)), 1)


func test_server_silence_returns_client_to_menu_with_no_world_or_actor() -> void:
	await _start([])
	var client: String = _directory.path_join("client.log")
	_launch(client, ["--nickname=Waiting"])
	await _wait_state(client, 1)
	_write(_control, "blackhole")
	assert_true(await _wait_for(_server, "SESSION BLACKHOLE"))
	var started: int = Time.get_ticks_msec()
	assert_true(await _wait_for(client, "SESSION REJECTED reason=server_timeout"), _read(client))
	assert_lte(float(Time.get_ticks_msec() - started) / 1000.0, 11.5)
	assert_true(await _wait_for(client, "SESSION EXIT"), _read(client))
	assert_has(_read(client), "SESSION RESET actors=0 map_unloaded=true")


func _start(options: PackedStringArray) -> void:
	var arguments: PackedStringArray = ["--server-role", "--control=" + _control]
	arguments.append_array(options)
	_launch(_server, arguments)
	assert_true(await _wait_for(_server, "SESSION READY"), _read(_server))


func _launch(log_path: String, options: PackedStringArray) -> int:
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(log_path), "-s", WORKER, "--",
		"--port=" + str(_port), "--stop-file=" + _stop]
	args.append_array(options)
	var pid: int = OS.create_process(OS.get_executable_path(), args)
	assert_gt(pid, 0)
	if pid > 0:
		_pids.append(pid)
	return pid


func _rejected(label: String, reason: String, options: PackedStringArray) -> void:
	var path: String = _directory.path_join(label + ".log")
	var pid: int = _launch(path, options)
	assert_true(await _wait_for(path, "SESSION REJECTED reason=" + reason), _read(path))
	await _wait_exit(pid)
	assert_false(_read(path).contains("NET CONNECTED"), _read(path))


func _wait_state(path: String, count: int, after_admission: bool = false) -> Dictionary:
	var deadline: int = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var content: String = _read(path)
		var admitted: bool = not after_admission
		for line: String in content.split("\n"):
			if line.contains("NET ACCEPT"):
				admitted = true
			if not admitted or not line.begins_with("SESSION STATE "):
				continue
			var state: Dictionary = JSON.parse_string(line.trim_prefix("SESSION STATE ")) as Dictionary
			if int(state.get("actors", -1)) == count and int(state.get("names", -1)) == count \
					and int(state.get("pending", -1)) == 0 \
					and int(state.get("closing", -1)) == 0:
				return state
		await get_tree().create_timer(0.03).timeout
	assert_true(false, _read(path))
	return {}


func _wait_for(path: String, marker: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _read(path).contains(marker):
			return true
		await get_tree().create_timer(0.03).timeout
	return false


func _wait_exit(pid: int) -> void:
	var deadline: int = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.03).timeout


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _write(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string(content)
