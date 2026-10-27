extends GutTest

var _menu: MainMenu


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	Game.detect_runtime_flags(PackedStringArray(), false)
	_menu = preload("res://src/ui/main_menu.tscn").instantiate() as MainMenu
	add_child(_menu)


func after_each() -> void:
	Net.disconnect_all()
	_menu.free()
	Net.local_nickname = "Player"
	Net.password = ""
	await get_tree().process_frame


func test_menu_controls_host_and_disconnect() -> void:
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(socket.bind(0, "127.0.0.1"), OK)
	_menu.port.value = socket.get_local_port()
	socket.close()
	_menu.nickname.text = "MenuHost"
	_menu.password_field.text = "secret"
	_menu.host_button.pressed.emit()
	assert_true(Net.is_connected)
	assert_eq(Net.nicknames.get(1), "MenuHost")
	assert_eq(Net.password, "secret")
	assert_true(_menu.host_button.disabled)
	assert_true(_menu.join_button.disabled)
	assert_false(_menu.disconnect_button.disabled)
	assert_false(_menu.nickname.editable)
	assert_true(_menu.password_field.secret)
	_menu.disconnect_button.pressed.emit()
	assert_false(Net.is_connected)
	assert_false(_menu.host_button.disabled)
	assert_false(_menu.join_button.disabled)
	assert_true(_menu.disconnect_button.disabled)
	assert_eq(_menu.status.text, "Disconnected")


func test_menu_displays_errors_and_keeps_retry_enabled() -> void:
	_menu.nickname.text = "!"
	_menu.host_button.pressed.emit()
	assert_has(_menu.status.text, "Host failed")
	assert_false(_menu.host_button.disabled)
	_menu.join_button.pressed.emit()
	assert_has(_menu.status.text, "Join failed")
	assert_false(_menu.join_button.disabled)
	Net.last_error = "protocol_mismatch"
	Net.connection_failed.emit()
	assert_has(_menu.status.text, "protocol_mismatch")
	assert_false(_menu.host_button.disabled)
