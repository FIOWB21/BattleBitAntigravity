# File-driven acceptance harness around production menu, UI and ENet RPCs.
extends SceneTree

var _options: Dictionary[String, String] = {}
var _menu: Control
var _chat: Node
var _messages: Array[Dictionary] = []
var _notices: Array[String] = []
var _sequence: int = 0
var _loads: int = 0
var _input_blocked: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.low_processor_usage_mode_sleep_usec = 1000
	for arg: String in OS.get_cmdline_user_args():
		_options[arg.get_slice("=", 0)] = arg.substr(arg.find("=") + 1)
	_open_menu()
	while not FileAccess.file_exists(_path("stop")):
		var command_path: String = _path("command.json")
		if FileAccess.file_exists(command_path):
			var command: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(command_path)) as Dictionary
			DirAccess.remove_absolute(ProjectSettings.globalize_path(command_path))
			await _execute(command)
		_write_report()
		await create_timer(0.02).timeout
	root.get_node("Net").disconnect_all()
	await process_frame
	_menu.free()
	await process_frame
	print("CHAT CLEANUP")
	quit()


func _open_menu() -> void:
	var game: Node = root.get_node("Game")
	var role: String = _options.get("--role", "client")
	game.is_dedicated = role == "dedicated"
	game.server_port = int(_options["--port"])
	_menu = load("res://src/ui/main_menu.tscn").instantiate() as Control
	_menu.name = "MainMenu"
	root.add_child(_menu)
	_chat = _menu.map_loader.chat
	_chat.message_received.connect(_received)
	_chat.notice_received.connect(_notice)
	_menu.map_loader.map_loaded.connect(_loaded)
	_menu.port.value = int(_options["--port"])
	_menu.nickname.text = _options["--nick"]
	if role == "listen":
		_menu.host_button.pressed.emit()
	elif role == "client":
		_menu.join_button.pressed.emit()
	print("CHAT READY")


func _execute(command: Dictionary) -> void:
	match String(command.get("op", "poll")):
		"setup":
			for actor: Node3D in _menu.map_loader.players.actors.values():
				actor.team_id = 2 if root.get_node("Net").nicknames.get(actor.network_owner_id) == "Enemy" else 1
		"spoof_team":
			for actor: Node3D in _menu.map_loader.players.actors.values():
				actor.team_id = 1
		"send":
			_chat.send(String(command.get("text", "")), bool(command.get("team", false)))
		"text":
			_menu.chat_panel.channel.selected = 1 if bool(command.get("team", false)) else 0
			_menu.chat_panel.field.text = String(command.get("text", ""))
			_menu.chat_panel.field.text_changed.emit(_menu.chat_panel.field.text)
		"key":
			var event: InputEventKey = InputEventKey.new()
			event.physical_keycode = int(command.get("key", KEY_T)) as Key
			event.keycode = event.physical_keycode
			event.pressed = true
			Input.parse_input_event(event)
			await process_frame
			if _menu.chat_panel.editing:
				_input_blocked = _menu.chat_panel._actor.input_reader.blocked
			event.pressed = false
			Input.parse_input_event(event)
			await process_frame
		"capture":
			await _capture(command)
	_sequence = int(command.get("sequence", _sequence))


func _capture(command: Dictionary) -> void:
	if command.has("text"):
		_menu.chat_panel.field.text = String(command["text"])
		_menu.chat_panel.field.text_changed.emit(String(command["text"]))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_path("capture.png")))


func _write_report() -> void:
	var peers: Array[String] = []
	for actor: Node3D in _menu.map_loader.players.actors.values():
		peers.append(root.get_node("Net").nicknames.get(actor.network_owner_id, ""))
	var report: Dictionary = {"sequence": _sequence, "messages": _messages, "notices": _notices,
		"actors": peers, "loads": _loads, "map": root.get_node("Game").map_id,
		"connected": root.get_node("Net").is_connected, "last_error": root.get_node("Net").last_error,
		"input_blocked": _input_blocked, "editing": _menu.chat_panel.editing if _menu.chat_panel != null else false}
	var output: FileAccess = FileAccess.open(_path("report.tmp"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report))
	output.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(_path("report.tmp")),
		ProjectSettings.globalize_path(_path("report.json")))


func _received(sender: int, nickname: String, text: String, team_only: bool) -> void:
	_messages.append({"sender": sender, "nickname": nickname, "text": text, "team": team_only})


func _notice(text: String) -> void:
	_notices.append(text)


func _loaded(_map_id: String) -> void:
	_loads += 1


func _path(suffix: String) -> String:
	return _options["--directory"].path_join(_options["--label"] + "." + suffix)
