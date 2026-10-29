# Shared by the matrix command and the regression integration test.
class_name NetMatrixCase
extends RefCounted

const WORKER: String = "res://tools/net_matrix_worker.gd"
const TIMEOUT_MS: int = 25000
var directory: String
var _tree: SceneTree
var _port: int
var _pids: Array[int] = []
var _failed: bool = false


func run(tree: SceneTree, ping: int, loss: float, jitter: int = 0,
		duplicates: float = 0.0, reorder: float = 0.0) -> Dictionary:
	_tree = tree
	_failed = false
	directory = "res://.godot/net_matrix_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	if socket.bind(0, "127.0.0.1") != OK:
		return {"ok": false, "reason": "No loopback port"}
	_port = socket.get_local_port()
	socket.close()
	var result: Dictionary = await _exercise(ping, loss, jitter, duplicates, reorder)
	await _finish()
	result["ok"] = not result.is_empty() and not _failed and _clean_logs()
	result["logs"] = directory
	return result


func _exercise(ping: int, loss: float, jitter: int, duplicates: float, reorder: float) -> Dictionary:
	if _launch("server", ["--role=server"]) <= 0 or not await _wait_text("server", "MATRIX READY"):
		return {}
	var args: PackedStringArray = ["--ping=" + str(ping), "--loss=" + str(loss),
		"--jitter=" + str(jitter), "--duplicate=" + str(duplicates), "--reorder=" + str(reorder)]
	if _launch("client", args) <= 0 or not await _wait_text("client", "MATRIX CLIENT "):
		return {}
	if not await _wait_text("server", "MATRIX SERVER "):
		return {}
	var client: Dictionary = _record("client", "MATRIX CLIENT ")
	var server: Dictionary = _record("server", "MATRIX SERVER ")
	if client.is_empty() or server.is_empty():
		return {}
	var requests: int = int(client.get("requests", 0))
	var accepted: int = int(server.get("accepted", 0))
	return {"ping_ms": ping, "loss_percent": loss, "jitter_ms": jitter,
		"duplicate_percent": duplicates, "reorder_percent": reorder,
		"client": client, "server": server,
		"rejected_percent": 100.0 * (requests - accepted) / maxi(1, requests)}


func _launch(role: String, options: PackedStringArray) -> int:
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(directory.path_join(role + ".log")),
		"-s", WORKER, "--", "--port=" + str(_port), "--directory=" + directory]
	args.append_array(options)
	var pid: int = OS.create_process(OS.get_executable_path(), args)
	if pid > 0:
		_pids.append(pid)
	else:
		_failed = true
	return pid


func _finish() -> void:
	# Sequential shutdown lets the server finish peer removal before closing ENet.
	for role: String in ["client", "server"]:
		FileAccess.open(directory.path_join(role + ".stop"), FileAccess.WRITE).close()
		var index: int = 1 if role == "client" else 0
		if index >= _pids.size():
			continue
		var pid: int = _pids[index]
		var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
		while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
			await _tree.create_timer(0.02).timeout
		if OS.is_process_running(pid):
			_failed = true
			OS.kill(pid)
	_pids.clear()


func _wait_text(role: String, expected: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		if _read(role).contains(expected):
			return true
		await _tree.create_timer(0.02).timeout
	_failed = true
	return false


func _record(role: String, prefix: String) -> Dictionary:
	for line: String in _read(role).split("\n"):
		if line.begins_with(prefix):
			var value: Variant = JSON.parse_string(line.trim_prefix(prefix))
			if value is Dictionary:
				return value as Dictionary
	return {}


func _read(role: String) -> String:
	var path: String = directory.path_join(role + ".log")
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _clean_logs() -> bool:
	for role: String in ["client", "server"]:
		var contents: String = _read(role)
		if not contents.contains("MATRIX CLEANUP actors=0"):
			return false
		for forbidden: String in ["SCRIPT ERROR", "ERROR:", "WARNING:", "timeout"]:
			if contents.contains(forbidden):
				return false
	return true


static func valid_result(result: Dictionary) -> bool:
	if not bool(result.get("ok", false)):
		return false
	var client: Dictionary = result["client"]
	var server: Dictionary = result["server"]
	return int(client["samples"]) > 30 and int(client["requests"]) >= 10 \
		and float(client["route_distance_m"]) > 10.0 and float(client["route_peak_m"]) > 5.0 \
		and int(client["route_ms"]) >= 5900 \
		and int(server["accepted"]) > 0 and int(server["accepted"]) <= int(client["requests"]) \
		and int(client["teleports"]) == 0 and int(client["history_misses"]) == 0 \
		and int(client["input_overflow"]) == 0 and int(server["snapshot_overflow"]) == 0 \
		and int(client["server_steps"]) == 0 and int(server["server_steps"]) > 360 \
		and int(server["pending"]) == 0 and is_finite(float(client["mean_error_m"]))
