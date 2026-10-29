extends GutTest

const WORKER: String = "res://tools/combat_worker.gd"
const TIMEOUT_MS: int = 25000
var _directory: String
var _port: int
var _pids: Array[int] = []


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_directory = "res://.godot/combat_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(socket.bind(0, "127.0.0.1"), OK)
	_port = socket.get_local_port()
	socket.close()


func after_each() -> void:
	for index: int in range(_pids.size()):
		FileAccess.open(_directory.path_join("stop%d" % index), FileAccess.WRITE).close()
	for pid: int in _pids:
		await _wait_exit(pid)
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()


func test_listen_host_and_two_clients_have_identical_killfeed_and_no_duplicate_respawns() -> void:
	await _exercise(false)


func test_dedicated_and_three_clients_deliver_private_hits_damage_and_two_respawns() -> void:
	await _exercise(true)


func _exercise(dedicated: bool) -> void:
	var role: String = "dedicated" if dedicated else "listen"
	var server: String = _directory.path_join("server.log")
	_launch(server, ["--role=" + role, "--nick=Alpha"])
	await _wait_text(server, "COMBAT READY")
	var clients: Array[String] = []
	var names: Array[String] = ["Bravo", "Charlie"]
	if dedicated:
		names.push_front("Alpha")
	for nickname: String in names:
		var path: String = _directory.path_join(nickname + ".log")
		clients.append(path)
		_launch(path, ["--nick=" + nickname])
	await _wait_text(server, "COMBAT SERVER DONE")
	for path: String in clients:
		await _wait_text(path, "COMBAT CLIENT DONE")
	var authoritative: Dictionary = _record(server, "COMBAT SERVER ")
	assert_true(authoritative.get("protected", false))
	assert_eq(authoritative.get("deadlines", []), [180.0, 180.0])
	assert_eq(authoritative.get("actors", 0), 3)
	assert_true(authoritative.get("identities", false))
	if not dedicated:
		clients.push_front(server)
	var feed: Array = []
	for path: String in clients:
		var replica: Dictionary = _record(path, "COMBAT RESULT ")
		_assert_replica(replica, authoritative, feed)
		feed = replica.get("feed", [])
	for index: int in range(_pids.size() - 1, -1, -1):
		FileAccess.open(_directory.path_join("stop%d" % index), FileAccess.WRITE).close()
		await _wait_exit(_pids[index])
	for path: String in clients + ([server] if dedicated else []):
		var log_text: String = _read(path)
		assert_has(log_text, "COMBAT CLEANUP actors=0")
		for forbidden: String in ["SCRIPT ERROR", "ERROR:", "WARNING:", "timeout"]:
			assert_false(log_text.contains(forbidden), log_text)
	print("COMBAT METRIC dedicated=", dedicated, " feed=", feed, " logs=", _directory)


func _assert_replica(replica: Dictionary, server: Dictionary, feed: Array) -> void:
	assert_eq(replica.get("deaths", []), server.get("deaths", []))
	assert_eq((replica.get("feed", []) as Array).size(), 2)
	if not feed.is_empty():
		assert_eq(replica.get("feed", []), feed)
	assert_eq(replica.get("actors", 0), 3)
	assert_true(replica.get("identities", false))
	assert_eq(replica.get("health", 0), 100)
	assert_eq(replica.get("victim_spawns", 0), 3)
	match String(replica.get("nickname", "")):
		"Alpha":
			assert_eq(replica.get("directions", -1), 0)
			var hits: Array = replica.get("hits", [])
			assert_eq(hits.size(), 4)
			if hits.size() == 4:
				assert_eq(hits[0], {"zone": 1.0, "killed": false})
				assert_eq(hits[1], {"zone": 0.0, "killed": true})
		"Bravo":
			assert_eq(replica.get("directions", 0), 4)
			assert_true(replica.get("damage", false))
			assert_true(replica.get("dead", false))
			assert_gt(replica.get("killcam_dot", 0.0), 0.99)
			assert_true((replica.get("hits", []) as Array).is_empty())
		"Charlie":
			assert_eq(replica.get("directions", -1), 0)
			assert_true((replica.get("hits", []) as Array).is_empty())


func _launch(path: String, options: PackedStringArray) -> int:
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(path), "-s", WORKER, "--",
		"--port=" + str(_port), "--report=" + _directory.path_join("report"),
		"--stop=" + _directory.path_join("stop%d" % _pids.size())]
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
	assert_false(OS.is_process_running(pid), "Combat worker exits normally")


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
