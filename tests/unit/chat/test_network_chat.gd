extends "res://tests/unit/combat/combat_fixture.gd"


func test_recipients_use_server_team_and_exclude_unready_or_unadmitted_players() -> void:
	Net.nicknames[42] = "Ally"
	Net.nicknames[43] = "Enemy"
	players.ready_peers[42] = true
	players.ready_peers[43] = true
	players.ready_peers[44] = true
	var enemy: Player = players._spawn_player({"peer_id": 43, "pose": loader.spawn_pose}) as Player
	players._container.add_child(enemy)
	enemy.team_id = 2
	actor.team_id = 1
	assert_eq(loader.chat.recipients(42, true), [42])
	assert_eq(loader.chat.recipients(42, false), [42, 43])
	actor.team_id = 0
	assert_true(loader.chat.recipients(42, true).is_empty())
	assert_true(loader.chat.recipients(999, false).is_empty())
	Net.nicknames.clear()


func test_unadmitted_requests_and_local_rpc_calls_cannot_authenticate_or_publish() -> void:
	var old_password: String = Game.admin_password
	Game.admin_password = "secret"
	var messages: Array[String] = []
	loader.chat.message_received.connect(func(_id: int, _nick: String, text: String, _team: bool) -> void:
		messages.append(text))
	loader.chat._accept(42, "/admin secret", false)
	loader.chat.submit("forged", false)
	loader.chat.deliver(42, "Forged", "forged", false)
	assert_false(loader.chat.admin.is_authorized(42, "secret"))
	assert_true(messages.is_empty())
	assert_true(loader.chat.policy._requests.is_empty())
	Game.admin_password = old_password


func test_chat_input_blocks_movement_buttons_and_buffered_actions_but_keeps_look() -> void:
	var reader: LocalInputReader = LocalInputReader.new()
	reader.yaw = 0.5
	reader.pitch = 0.2
	reader._weapon_slot = 2
	reader._melee = true
	reader.set_blocked(true)
	Input.action_press(InputActions.MOVE_FORWARD)
	Input.action_press(InputActions.FIRE)
	var inp: PlayerInput = reader.read_input()
	Input.action_release(InputActions.MOVE_FORWARD)
	Input.action_release(InputActions.FIRE)
	assert_eq(inp.move, Vector2.ZERO)
	assert_eq(inp.buttons, 0)
	assert_eq(inp.weapon_slot, 0)
	assert_false(inp.melee)
	assert_eq(inp.yaw, 0.5)
	assert_eq(inp.pitch, 0.2)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(50, 50)
	reader.handle_input_event(motion)
	assert_eq(reader.yaw, 0.5)
	reader.set_blocked(false)
	assert_false(reader.blocked)


func test_panel_reuses_plain_labels_masks_password_and_restores_input() -> void:
	var panel: ChatPanel = ChatPanel.new()
	panel.chat = loader.chat
	add_child(panel)
	var count: int = get_tree().get_node_count()
	for index: int in range(100):
		panel._message(42, "Ally", "text", true)
	assert_eq(panel._rows.size(), loader.chat.config.history_count)
	assert_eq(get_tree().get_node_count(), count)
	assert_eq(panel._rows.back().text, "[TEAM] Ally: text")
	panel._text_changed("/admin secret")
	assert_true(panel.field.secret)
	panel._actor = actor
	panel.editing = true
	actor.input_reader.set_blocked(true)
	panel.close()
	assert_false(actor.input_reader.blocked)
	assert_false(panel.editing)
	assert_false(panel.field.secret)
	assert_eq(panel.field.text, "")
	panel._reset()
	assert_eq(panel._rows.back().text, "")
	panel.free()


func test_map_geometry_replacement_keeps_actor_and_rejects_unknown_maps_atomically() -> void:
	var instance: int = actor.get_instance_id()
	var geometry: Node3D = loader.current_map
	assert_false(loader._replace_geometry("missing_map"))
	assert_eq(loader.current_map, geometry)
	assert_eq(players.actors[42].get_instance_id(), instance)
	assert_true(loader._replace_geometry("testbed"))
	assert_ne(loader.current_map, geometry)
	assert_eq(players.actors[42].get_instance_id(), instance)
	assert_eq(loader.current_data.id, &"testbed")
	await get_tree().process_frame


func test_long_history_stays_bounded_and_scrolls_to_the_last_line() -> void:
	var panel: ChatPanel = ChatPanel.new()
	panel.chat = loader.chat
	add_child(panel)
	for index: int in range(loader.chat.config.history_count):
		panel._message(42, "Ally", "界".repeat(loader.chat.config.max_length), true)
	for frame: int in range(4):
		await get_tree().process_frame
	var bar: VScrollBar = panel._scroll.get_v_scroll_bar()
	assert_gt(bar.max_value, bar.page)
	assert_almost_eq(bar.value, bar.max_value - bar.page, 1.0)
	assert_almost_eq(panel._scroll.size.y, ChatPanel.ROW_HEIGHT * loader.chat.config.history_count, 1.0)
	panel.free()


func test_chat_key_fallback_preserves_the_existing_t_last_weapon_binding() -> void:
	var panel: ChatPanel = ChatPanel.new()
	var event: InputEventKey = InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_T
	event.keycode = KEY_T
	assert_true(event.is_action_pressed(InputActions.CHAT))
	assert_true(event.is_action_pressed(InputActions.SWITCH_WEAPON_LAST))
	assert_false(panel._opens_chat(event))
	event.keycode = KEY_ENTER
	event.physical_keycode = KEY_ENTER
	assert_true(panel._opens_chat(event))
	event.pressed = false
	assert_false(panel._opens_chat(event))
	panel.free()


func test_map_restart_resets_life_equipment_pose_history_and_deadlines() -> void:
	_kill()
	assert_eq(actor.life.state, PlayerLife.State.SPAWN_SELECT)
	actor.global_position += Vector3(10, 0, 10)
	actor.weapon.ammo_in_mag = 0
	var instance: int = actor.get_instance_id()
	players.respawns.restart_for_map(Net.tick)
	assert_eq(actor.life.state, PlayerLife.State.ALIVE)
	assert_eq(actor.health_component.current, actor.health_component.max_health)
	assert_eq(actor.weapon.ammo_in_mag, actor.weapon.data.mag_size)
	assert_eq(actor.global_transform, players.respawn_pose(42))
	assert_eq(actor.get_instance_id(), instance)
	assert_true(players.respawns.deadlines.is_empty())
	assert_false(players.respawns.spawning)
	assert_eq(players.respawns.spawn_ticks[42], Net.tick)
	assert_eq(actor.server_sim.input_queue.last_input_tick, Net.tick)
