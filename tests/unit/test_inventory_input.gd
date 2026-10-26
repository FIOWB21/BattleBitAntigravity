extends GutTest


func _action(action: StringName) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func test_slot_presses_are_buffered_once_and_latest_slot_wins() -> void:
	var reader: LocalInputReader = LocalInputReader.new()
	for slot: int in range(1, Loadout.SLOT_COUNT + 1):
		reader.handle_input_event(_action(LocalInputReader.SLOT_ACTIONS[slot - 1]))
		var inp: PlayerInput = reader.read_input()
		assert_eq(inp.weapon_slot, slot)
		assert_eq(reader.read_input().weapon_slot, 0)
	reader.handle_input_event(_action(InputActions.SLOT_1))
	reader.handle_input_event(_action(InputActions.SLOT_2))
	assert_eq(reader.read_input().weapon_slot, 2)


func test_wheel_and_quick_swap_survive_press_release_between_physics_ticks() -> void:
	var reader: LocalInputReader = LocalInputReader.new()
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	reader.handle_input_event(wheel)
	wheel.pressed = false
	reader.handle_input_event(wheel)
	assert_eq(reader.read_input().weapon_cycle, 1)
	assert_eq(reader.read_input().weapon_cycle, 0)
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	reader.handle_input_event(wheel)
	assert_eq(reader.read_input().weapon_cycle, -1)
	reader.handle_input_event(_action(InputActions.SWITCH_WEAPON_LAST))
	assert_true(reader.read_input().last_weapon)
	assert_false(reader.read_input().last_weapon)


func test_opposite_wheel_events_cancel_and_key_echo_does_not_repeat_slot() -> void:
	var reader: LocalInputReader = LocalInputReader.new()
	reader.handle_input_event(_action(InputActions.SWITCH_WEAPON_NEXT))
	reader.handle_input_event(_action(InputActions.SWITCH_WEAPON_PREV))
	assert_eq(reader.read_input().weapon_cycle, 0)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_2
	key.pressed = true
	reader.handle_input_event(key)
	assert_eq(reader.read_input().weapon_slot, 2)
	key.echo = true
	reader.handle_input_event(key)
	assert_eq(reader.read_input().weapon_slot, 0)


func test_default_loadout_has_distinct_primary_secondary_and_empty_equipment_slots() -> void:
	var loadout: Loadout = load("res://src/weapons/data/default_loadout.tres") as Loadout
	assert_eq(loadout.primary.category, WeaponData.Category.AR)
	assert_eq(loadout.secondary.category, WeaponData.Category.PISTOL)
	for slot: int in range(3, 6):
		assert_null(loadout.item_at(slot))
	assert_eq(loadout.draw_time_at(-1), 0.0)
	assert_eq(loadout.draw_time_at(1), loadout.primary.draw_time)
	assert_eq(loadout.draw_time_at(2), loadout.secondary.draw_time)
	var actions: Array[InputEvent] = InputMap.action_get_events(InputActions.SWITCH_WEAPON_LAST)
	assert_eq((actions[0] as InputEventKey).physical_keycode, KEY_T)
