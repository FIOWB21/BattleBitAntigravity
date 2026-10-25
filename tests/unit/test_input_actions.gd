extends GutTest


func test_all_input_action_constants_exist_in_input_map() -> void:
	var expected_actions: Array[StringName] = [
		InputActions.MOVE_FORWARD,
		InputActions.MOVE_BACK,
		InputActions.MOVE_LEFT,
		InputActions.MOVE_RIGHT,
		InputActions.JUMP,
		InputActions.SPRINT,
		InputActions.CROUCH,
		InputActions.PRONE,
		InputActions.LEAN_LEFT,
		InputActions.LEAN_RIGHT,
		InputActions.FIRE,
		InputActions.AIM,
		InputActions.RELOAD,
		InputActions.SWITCH_WEAPON_NEXT,
		InputActions.SWITCH_WEAPON_PREV,
		InputActions.SLOT_1,
		InputActions.SLOT_2,
		InputActions.SLOT_3,
		InputActions.SLOT_4,
		InputActions.SLOT_5,
		InputActions.USE_GADGET,
		InputActions.INTERACT,
		InputActions.MELEE,
		InputActions.THROW_GRENADE,
		InputActions.SCOREBOARD,
		InputActions.CHAT,
		InputActions.VOICE,
		InputActions.MAP,
		InputActions.PAUSE_MENU,
		InputActions.SQUAD_MENU,
		InputActions.SPOT,
		InputActions.VEHICLE_SEAT_NEXT,
		InputActions.VEHICLE_EXIT,
	]
	assert_eq(expected_actions.size(), 33, "Must have 33 expected actions")
	assert_eq(InputActions.ALL_ACTIONS.size(), 33, "ALL_ACTIONS must contain 33 actions")

	for action: StringName in expected_actions:
		assert_true(InputMap.has_action(action), "InputMap must have action: " + String(action))
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		assert_gt(events.size(), 0, "Action must have at least one bound InputEvent: " + String(action))
		assert_has(InputActions.ALL_ACTIONS, action, "ALL_ACTIONS must include: " + String(action))


func test_script_constants_match_input_map() -> void:
	var script_ref: Script = InputActions
	var constants: Dictionary = script_ref.get_script_constant_map()
	var string_name_count: int = 0

	for const_key: Variant in constants.keys():
		var val: Variant = constants[const_key]
		if val is StringName:
			string_name_count += 1
			var action_name: StringName = val
			assert_true(
				InputMap.has_action(action_name),
				"Constant %s (%s) must exist in InputMap" % [str(const_key), String(action_name)]
			)
			assert_has(
				InputActions.ALL_ACTIONS,
				action_name,
				"Constant %s (%s) must be in ALL_ACTIONS" % [str(const_key), String(action_name)]
			)

	assert_eq(string_name_count, 33, "InputActions must declare exactly 33 StringName constants")
