extends GutTest

var _inventory: Inventory
var _inp: PlayerInput
var _shots: Array[Vector2i] = []


func before_each() -> void:
	_shots.clear()
	_inp = PlayerInput.new()
	_inventory = Inventory.new()
	var loadout: Loadout = Loadout.new()
	loadout.primary = _profile(0.1)
	loadout.secondary = _profile(0.2)
	_inventory.loadout = loadout
	add_child_autofree(_inventory)
	for slot: int in range(1, 3):
		_inventory.weapon_at(slot).fired.connect(
			func(tick: int) -> void: _shots.append(Vector2i(slot, tick)))


func _profile(draw_time: float) -> WeaponData:
	var data: WeaponData = WeaponData.new()
	data.fire_modes = [WeaponData.FireMode.AUTO]
	data.rpm = 600.0
	data.draw_time = draw_time
	return data


func _step(tick: int, slot: int = 0, buttons: int = 0, cycle: int = 0,
		last: bool = false, allowed: bool = true) -> void:
	_inp.tick = tick
	_inp.buttons = buttons
	_inp.weapon_slot = slot
	_inp.weapon_cycle = cycle
	_inp.last_weapon = last
	_inventory.simulate(_inp, allowed)
	var weapon: Weapon = _inventory.active_weapon()
	if weapon != null:
		weapon.simulate(_inp)


func test_change_blocks_fire_until_exact_draw_end_and_preserves_instances() -> void:
	var primary: Weapon = _inventory.weapon_at(1)
	var secondary: Weapon = _inventory.weapon_at(2)
	_step(0, 2, PlayerInput.BTN_FIRE)
	assert_eq(_inventory.phase, Inventory.Phase.HOLSTERING)
	assert_eq(_inventory.end_tick, 6)
	for tick: int in range(1, 6):
		_step(tick, 0, PlayerInput.BTN_FIRE)
	_step(6, 0, PlayerInput.BTN_FIRE)
	assert_eq(_inventory.active_slot, 2)
	assert_eq(secondary.state, Weapon.State.SWITCHING_IN)
	assert_eq(_inventory.end_tick, 18)
	for tick: int in range(7, 18):
		_step(tick, 0, PlayerInput.BTN_FIRE)
	assert_eq(_shots.size(), 0)
	_step(18, 0, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [Vector2i(2, 18)])
	assert_eq(_inventory.phase, Inventory.Phase.READY)
	assert_eq(_inventory.weapon_at(1), primary)
	assert_eq(_inventory.weapon_at(2), secondary)


func test_each_weapon_keeps_magazine_reserve_and_mode_across_round_trip() -> void:
	var primary: Weapon = _inventory.weapon_at(1)
	var secondary: Weapon = _inventory.weapon_at(2)
	primary.ammo_in_mag = 7
	primary.reserve_ammo = 23
	secondary.ammo_in_mag = 3
	secondary.reserve_ammo = 9
	_step(0, 2)
	_step(6)
	_step(18, 0, PlayerInput.BTN_FIRE)
	_step(19, 1)
	_step(31)
	_step(37)
	assert_eq(primary.ammo_in_mag, 7)
	assert_eq(primary.reserve_ammo, 23)
	assert_eq(secondary.ammo_in_mag, 2)
	assert_eq(secondary.reserve_ammo, 9)
	assert_eq(primary.fire_mode, WeaponData.FireMode.AUTO)
	assert_eq(secondary.fire_mode, WeaponData.FireMode.AUTO)


func test_wheel_wrap_empty_slots_and_last_weapon_toggle() -> void:
	_step(0, 0, 0, -1)
	_step(6)
	_step(18)
	assert_eq(_inventory.active_slot, 2)
	assert_eq(_inventory.last_weapon_slot, 1)
	_step(19, 0, 0, 0, true)
	_step(31)
	_step(37)
	assert_eq(_inventory.active_slot, 1)
	assert_eq(_inventory.last_weapon_slot, 2)
	_step(38, 0, 0, 0, true)
	_step(44)
	_step(56)
	assert_eq(_inventory.active_slot, 2)
	assert_eq(_inventory.next_slot(2, 1), 1)
	assert_eq(_inventory.next_slot(1, -1), 2)


func test_empty_invalid_current_and_missing_last_requests_do_nothing() -> void:
	for slot: int in [0, 1, 3, 4, 5, -1, 99]:
		_step(_inp.tick + 1, slot)
		assert_eq(_inventory.active_slot, 1)
		assert_eq(_inventory.phase, Inventory.Phase.READY)
	_step(100, 0, 0, 0, true)
	assert_eq(_inventory.phase, Inventory.Phase.READY)
	assert_null(_inventory.weapon_at(-1))
	assert_null(_inventory.weapon_at(99))


func test_busy_duplicate_old_ticks_and_forbidden_requests_are_ignored() -> void:
	_step(0, 2)
	_step(1, 1)
	_step(0, 1)
	_step(6, 1)
	assert_eq(_inventory.active_slot, 2)
	_step(7, 1)
	_step(18)
	_step(19, 1, 0, 0, false, false)
	assert_eq(_inventory.active_slot, 2)
	assert_eq(_inventory.phase, Inventory.Phase.READY)


func test_switch_cancels_reload_without_transferring_ammo() -> void:
	var weapon: Weapon = _inventory.active_weapon()
	weapon.ammo_in_mag = 5
	_step(0, 0, PlayerInput.BTN_RELOAD)
	assert_eq(weapon.state, Weapon.State.RELOADING)
	_step(1, 2, PlayerInput.BTN_FIRE | PlayerInput.BTN_RELOAD)
	assert_eq(weapon.state, Weapon.State.SWITCHING_OUT)
	_step(7)
	_step(19)
	assert_eq(weapon.ammo_in_mag, 5)
	assert_eq(weapon.reserve_ammo, 150)
	assert_eq(_shots.size(), 0)


func test_reload_can_reject_switch_without_changing_history() -> void:
	var weapon: Weapon = _inventory.active_weapon()
	weapon.data.reload_interrupt_on_switch = false
	weapon.ammo_in_mag = 5
	_step(0, 0, PlayerInput.BTN_RELOAD)
	_step(1, 2)
	assert_eq(_inventory.phase, Inventory.Phase.READY)
	assert_eq(_inventory.active_slot, 1)
	assert_eq(_inventory.last_weapon_slot, 0)
	assert_eq(weapon.state, Weapon.State.RELOADING)
	_step(132)
	_step(133, 2)
	assert_eq(_inventory.phase, Inventory.Phase.HOLSTERING)


func test_non_weapon_slots_are_selectable_but_have_no_firearm() -> void:
	var gadget: EquipmentData = EquipmentData.new()
	gadget.draw_time = 0.05
	_inventory.loadout.gadget_1 = gadget
	_inventory.loadout.gadget_2 = gadget
	_inventory.loadout.grenade_melee = gadget
	_step(0, 3)
	_step(6)
	_step(9)
	assert_eq(_inventory.active_slot, 3)
	assert_null(_inventory.active_weapon())
	assert_eq(_inventory.last_weapon_slot, 1)
	_step(10, 4, PlayerInput.BTN_FIRE)
	_step(13)
	_step(16)
	assert_eq(_inventory.active_slot, 4)
	_step(17, 5)
	_step(20)
	_step(23)
	assert_eq(_inventory.active_slot, 5)
	_step(24, 0, 0, 0, true)
	_step(27)
	_step(33)
	assert_eq(_inventory.active_slot, 1)
	assert_eq(_shots.size(), 0)


func test_empty_loadout_and_single_slot_have_safe_cycle() -> void:
	var empty: Inventory = Inventory.new()
	empty.loadout = Loadout.new()
	add_child_autofree(empty)
	assert_eq(empty.active_slot, 0)
	assert_eq(empty.next_slot(0, 1), 0)
	_inventory.loadout.secondary = null
	assert_eq(_inventory.next_slot(1, 1), 1)
	assert_eq(_inventory.next_slot(1, -1), 1)
	assert_eq(_inventory.next_slot(1, 0), 1)


func test_network_client_cannot_switch_or_spend_ammo() -> void:
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 9), OK)
	api.multiplayer_peer = peer
	var path: NodePath = _inventory.get_path()
	get_tree().set_multiplayer(api, path)
	_step(0, 2, PlayerInput.BTN_FIRE)
	_step(100, 2, PlayerInput.BTN_FIRE)
	assert_eq(_inventory.active_slot, 1)
	assert_eq(_inventory.phase, Inventory.Phase.READY)
	assert_eq(_inventory.active_weapon().ammo_in_mag, 30)
	assert_eq(_shots.size(), 0)
	get_tree().set_multiplayer(null, path)
	peer.close()


func test_inventory_uses_weapon_clock_for_custom_tick_rate() -> void:
	_inventory.weapon_at(1).ticks_per_second = 30
	_inventory.weapon_at(2).ticks_per_second = 30
	_step(0, 2, PlayerInput.BTN_FIRE)
	assert_eq(_inventory.end_tick, 3)
	_step(3, 0, PlayerInput.BTN_FIRE)
	assert_eq(_inventory.end_tick, 9)
	_step(8, 0, PlayerInput.BTN_FIRE)
	assert_eq(_shots.size(), 0)
	_step(9, 0, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [Vector2i(2, 9)])


func test_initial_secondary_and_zero_negative_draw_times() -> void:
	var inventory: Inventory = Inventory.new()
	inventory.loadout = Loadout.new()
	inventory.loadout.secondary = _profile(0.0)
	inventory.loadout.gadget_1 = EquipmentData.new()
	inventory.loadout.gadget_1.draw_time = -1.0
	add_child_autofree(inventory)
	assert_eq(inventory.active_slot, 2)
	assert_eq(inventory.active_weapon().state, Weapon.State.IDLE)
	_inp.weapon_slot = 3
	_inp.tick = 0
	inventory.simulate(_inp)
	assert_eq(inventory.end_tick, 1)
	_inp.weapon_slot = 0
	_inp.tick = 1
	inventory.simulate(_inp)
	assert_eq(inventory.active_slot, 3)
	assert_eq(inventory.end_tick, 2)
	_inp.tick = 2
	inventory.simulate(_inp)
	assert_eq(inventory.phase, Inventory.Phase.READY)


func test_signals_report_committed_selection_and_finished_weapon_state() -> void:
	var events: Array[String] = []
	_inventory.switch_started.connect(
		func(from_slot: int, to_slot: int) -> void: events.append("%d>%d" % [from_slot, to_slot]))
	_inventory.active_slot_changed.connect(
		func(slot: int, weapon: Weapon) -> void:
			events.append("active:%d" % slot)
			assert_eq(weapon.state, Weapon.State.SWITCHING_IN))
	_inventory.switch_finished.connect(
		func(slot: int) -> void:
			events.append("ready:%d" % slot)
			assert_eq(_inventory.active_weapon().state, Weapon.State.IDLE))
	_step(0, 2)
	_step(6)
	_step(18, 0, PlayerInput.BTN_FIRE)
	assert_eq(events, ["1>2", "active:2", "ready:2"])
	assert_eq(_shots, [Vector2i(2, 18)])
