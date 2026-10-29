extends GutTest

const TIMEOUT_MS: int = 12000
var _directory: String
var _port: int
var _sequence: int = 0
var _pids: Dictionary[String, int] = {}
var _reports: Dictionary[String, Dictionary] = {}


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_reports.clear()
	_directory = "res://.godot/chat_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(socket.bind(0, "127.0.0.1"), OK)
	_port = socket.get_local_port()
	socket.close()


func after_each() -> void:
	for label: String in _pids:
		FileAccess.open(_path(label, "stop"), FileAccess.WRITE).close()
	for label: String in _pids:
		var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
		while OS.is_process_running(_pids[label]) and Time.get_ticks_msec() < deadline:
			await get_tree().create_timer(0.02).timeout
		if OS.is_process_running(_pids[label]):
			OS.kill(_pids[label])
		var log_text: String = FileAccess.get_file_as_string(_path(label, "log"))
		assert_has(log_text, "CHAT CLEANUP", log_text)
		for forbidden: String in ["SCRIPT ERROR", "ERROR:", "WARNING:", "integration_password"]:
			assert_false(log_text.contains(forbidden), log_text)
	_pids.clear()


func test_dedicated_team_privacy_sanitizing_rate_limit_and_admin_commands() -> void:
	await _exercise(true)


func test_listen_team_privacy_sanitizing_rate_limit_and_admin_commands() -> void:
	await _exercise(false)


func _exercise(dedicated: bool) -> void:
	_launch("server", "Ally", "dedicated" if dedicated else "listen")
	await _wait("server", "connected", true)
	_launch("sender", "Sender")
	_launch("enemy", "Enemy")
	if dedicated:
		_launch("ally", "Ally")
	await _wait_actors("server", 3)
	await _wait_actors("sender", 3)
	await _wait_actors("enemy", 3)
	var ally: String = "ally" if dedicated else "server"
	await _wait_actors(ally, 3)
	await _command("server", {"op": "setup"})
	await _chat_checks(ally)
	await _admin_checks(ally)
	print("CHAT METRIC dedicated=", dedicated, " logs=", _directory)


func _chat_checks(ally: String) -> void:
	await _command("enemy", {"op": "spoof_team"})
	await _command("sender", {"op": "key", "key": KEY_ENTER})
	assert_true(_report("sender").get("editing", false))
	await _command("sender", {"op": "key", "key": KEY_ESCAPE})
	assert_false(_report("sender").get("editing", true))
	await _command("sender", {"op": "key", "key": KEY_ENTER})
	await _command("sender", {"op": "text", "text": "private [b]привет[/b]\n", "team": true})
	await _command("sender", {"op": "key", "key": KEY_ENTER})
	assert_false(_report("sender").get("editing", true))
	await _wait_messages(ally, 1)
	await _wait_messages("sender", 1)
	assert_eq(_texts("sender"), ["private (b)привет(/b)"])
	assert_true(_report("sender").get("input_blocked", false))
	await _command("sender", {"op": "send", "text": "global", "team": false})
	await _wait_messages("enemy", 1)
	assert_eq(_texts("enemy"), ["global"], "Enemy never receives the private payload")
	await _command("sender", {"op": "send", "text": "x".repeat(300)})
	await _wait_messages("enemy", 2)
	assert_eq(_texts("enemy")[1].length(), 256)
	await _command("sender", {"op": "send", "text": "spam denied"})
	await _command("sender", {"op": "send", "text": "spam denied"})
	await _command("enemy", {"op": "send", "text": "enemy private", "team": true})
	await _wait_messages("enemy", 3)
	assert_eq(_texts("enemy")[2], "enemy private")
	assert_eq(_texts("sender").size(), 3)
	assert_eq(_texts(ally).size(), 3)
	assert_false(str(_report("enemy")).contains("private (b)"))


func _admin_checks(ally: String) -> void:
	await _command(ally, {"op": "send", "text": "/say unauthorized"})
	await _wait_notices(ally, 1)
	assert_has(str(_report(ally)), "Admin authentication required")
	await _command(ally, {"op": "send", "text": "/admin wrong"})
	await _wait_notices(ally, 2)
	assert_has(str(_report(ally)), "Admin authentication failed")
	await _command(ally, {"op": "send", "text": "/admin integration_password"})
	await _wait_notices(ally, 3)
	assert_has(str(_report(ally)), "Admin authenticated.")
	await get_tree().create_timer(5.1).timeout
	await _command(ally, {"op": "send", "text": "/say [b]announcement[/b]"})
	await _wait_messages("enemy", 4)
	assert_eq(_texts("enemy")[3], "(b)announcement(/b)")
	await _command(ally, {"op": "send", "text": "/map missing_map"})
	await _wait_notices(ally, 4)
	assert_eq(_report("server").get("map"), "testbed")
	await _command(ally, {"op": "send", "text": "/map testbed"})
	await _wait_actors("server", 3)
	await _wait("sender", "loads", 2)
	await _wait_actors("sender", 3)
	await _wait_actors("enemy", 3)
	await _wait_actors(ally, 3)
	await get_tree().create_timer(5.1).timeout
	await _command(ally, {"op": "send", "text": "/kick Enemy"})
	await _wait("enemy", "connected", false)
	assert_eq(_report("enemy").get("last_error"), "admin_kick")
	await _wait_actors("server", 2)
	await _command("sender", {"op": "send", "text": "after map"})
	await _wait_messages(ally, 5)
	assert_eq(_texts(ally).back(), "after map")


func _launch(label: String, nickname: String, role: String = "client") -> void:
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(_path(label, "log")), "-s", "res://tools/chat_worker.gd", "--",
		"--directory=" + _directory, "--label=" + label, "--role=" + role,
		"--nick=" + nickname, "--port=" + str(_port)]
	if role != "client":
		args.append("--admin-password=integration_password")
	var pid: int = OS.create_process(OS.get_executable_path(), args)
	assert_gt(pid, 0)
	_pids[label] = pid


func _command(label: String, command: Dictionary) -> void:
	_sequence += 1
	command["sequence"] = _sequence
	var output: FileAccess = FileAccess.open(_path(label, "command.tmp"), FileAccess.WRITE)
	output.store_string(JSON.stringify(command))
	output.close()
	assert_eq(DirAccess.rename_absolute(ProjectSettings.globalize_path(_path(label, "command.tmp")),
		ProjectSettings.globalize_path(_path(label, "command.json"))), OK)
	await _wait(label, "sequence", _sequence)


func _report(label: String) -> Dictionary:
	var last_valid: Dictionary = _reports.get(label, {})
	var input: FileAccess = FileAccess.open(_path(label, "report.json"), FileAccess.READ)
	if input == null:
		return last_valid
	var parser: JSON = JSON.new()
	if parser.parse(input.get_as_text()) != OK:
		return last_valid
	var parsed: Variant = parser.data
	if parsed is Dictionary:
		_reports[label] = parsed as Dictionary
	return _reports.get(label, last_valid)


func _texts(label: String) -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in _report(label).get("messages", []):
		result.append(String(entry["text"]))
	return result


func _wait(label: String, key: String, expected: Variant) -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while _report(label).get(key) != expected and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.02).timeout
	assert_eq(_report(label).get(key), expected, label + ": " + key)


func _wait_actors(label: String, count: int) -> void:
	await _wait_count(label, "actors", count)


func _wait_messages(label: String, count: int) -> void:
	await _wait_count(label, "messages", count)


func _wait_notices(label: String, count: int) -> void:
	await _wait_count(label, "notices", count)


func _wait_count(label: String, key: String, count: int) -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while (_report(label).get(key, []) as Array).size() != count and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.02).timeout
	assert_eq((_report(label).get(key, []) as Array).size(), count, label + ": " + key)


func _path(label: String, suffix: String) -> String:
	return _directory.path_join(label + "." + suffix)
