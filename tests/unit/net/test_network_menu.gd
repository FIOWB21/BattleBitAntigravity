extends GutTest

var _menu: MainMenu


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	Game.detect_runtime_flags(PackedStringArray(), false)
	Game.map_id = "testbed"
	_menu = preload("res://src/ui/main_menu.tscn").instantiate() as MainMenu
	add_child(_menu)


func after_each() -> void:
	Net.disconnect_all()
	_menu.free()
	Game.map_id = "testbed"
	Net.local_nickname = "Player"
	await get_tree().process_frame


func test_host_loads_world_escape_opens_menu_and_disconnect_restores_lobby() -> void:
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(socket.bind(0, "127.0.0.1"), OK)
	_menu.port.value = socket.get_local_port()
	socket.close()
	_menu.host_button.pressed.emit()
	assert_true(Game.is_in_game())
	assert_false(_menu.get_node("Center").visible)
	assert_eq(_menu.map_loader.players.actors.size(), 1)
	var actor: Player = _menu.map_loader.players.actors[1]
	var escape: InputEventAction = InputEventAction.new()
	escape.action = InputActions.PAUSE_MENU
	escape.pressed = true
	_menu._input(escape)
	assert_true(_menu.get_node("Center").visible)
	assert_false(actor.is_mouse_captured())
	_menu._input(escape)
	assert_false(_menu.get_node("Center").visible)
	assert_true(actor.is_mouse_captured())
	_menu.disconnect_button.pressed.emit()
	assert_true(_menu.get_node("Center").visible)
	assert_null(_menu.map_loader.current_map)
	assert_true(Game.is_in_menu())


func test_unknown_host_map_fails_before_opening_transport() -> void:
	Game.map_id = "missing_map"
	_menu.host_button.pressed.emit()
	assert_false(Net.is_connected)
	assert_null(_menu.map_loader.current_map)
	assert_has(_menu.status.text, "Map failed")
	assert_true(_menu.get_node("Center").visible)
	assert_false(_menu.host_button.disabled)


func test_failed_host_credentials_unload_prepared_map_and_allow_retry() -> void:
	_menu.nickname.text = "!"
	_menu.host_button.pressed.emit()
	assert_false(Net.is_connected)
	assert_null(_menu.map_loader.current_map)
	assert_has(_menu.status.text, "Host failed")
	assert_true(_menu.get_node("Center").visible)
	assert_false(_menu.host_button.disabled)
