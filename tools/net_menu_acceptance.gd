# Render the actual lobby and exercise its Host / Disconnect / failed Join controls.
extends SceneTree

var _menu: Control
var _net: Node
var _ok: bool = true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_net = root.get_node("Net")
	_menu = load("res://src/ui/main_menu.tscn").instantiate() as Control
	root.add_child(_menu)
	await process_frame
	await _capture("ready")
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	_ok = socket.bind(0, "127.0.0.1") == OK
	_menu.port.value = socket.get_local_port()
	socket.close()
	_menu.nickname.text = "LobbyHost"
	_menu.host_button.pressed.emit()
	_ok = _ok and _menu.host_button.disabled and _menu.join_button.disabled
	_ok = _ok and _net.is_connected and _net.nicknames.get(1) == "LobbyHost"
	await _capture("hosting")
	_menu.disconnect_button.pressed.emit()
	_ok = _ok and not _net.is_connected and not _menu.host_button.disabled
	_net.config = _net.config.duplicate() as NetworkConfig
	_net.config.handshake_timeout_seconds = 0.2
	_menu.join_button.pressed.emit()
	await create_timer(0.4).timeout
	_ok = _ok and _menu.status.text == "Connection failed: connection_failed"
	_ok = _ok and not _menu.join_button.disabled
	await _capture("failed_join")
	print("NET MENU ACCEPTANCE ", "OK" if _ok else "FAIL", " status=", _menu.status.text)
	_net.disconnect_all()
	_menu.queue_free()
	await process_frame
	quit(0 if _ok else 1)


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	var path: String = "res://.godot/net_menu_%s.png" % label
	_ok = _ok and screenshot.save_png(path) == OK
