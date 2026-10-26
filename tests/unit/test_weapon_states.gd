extends GutTest

var _shots: Array[int] = []
var _ammo_events: Array[Vector2i] = []
var _reload_starts: int = 0
var _reload_finishes: int = 0


func before_each() -> void:
	_shots.clear()
	_ammo_events.clear()
	_reload_starts = 0
	_reload_finishes = 0


func _weapon() -> Weapon:
	var profile: WeaponData = load("res://src/weapons/data/ar.tres").duplicate() as WeaponData
	profile.rpm = 600.0
	profile.reload_time = 0.2
	profile.reload_empty_time = 0.3
	profile.draw_time = 0.1
	var weapon: Weapon = Weapon.new()
	weapon.data = profile
	weapon.ticks_per_second = 60
	weapon.fired.connect(func(tick: int) -> void: _shots.append(tick))
	weapon.ammo_changed.connect(
		func(mag: int, reserve: int) -> void: _ammo_events.append(Vector2i(mag, reserve)))
	weapon.reload_started.connect(func() -> void: _reload_starts += 1)
	weapon.reload_finished.connect(func() -> void: _reload_finishes += 1)
	add_child_autofree(weapon)
	return weapon


func _step(weapon: Weapon, tick: int, buttons: int = 0, blocked: bool = false) -> void:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = tick
	inp.buttons = buttons
	weapon.simulate(inp, blocked)


func test_reload_blocks_fire_until_exact_end_tick() -> void:
	var weapon: Weapon = _weapon()
	_step(weapon, 0, PlayerInput.BTN_FIRE)
	_step(weapon, 1, PlayerInput.BTN_RELOAD | PlayerInput.BTN_FIRE)
	assert_eq(weapon.state, Weapon.State.RELOADING)
	assert_eq(weapon.reload_end_tick, 13)
	for tick: int in range(2, 13):
		_step(weapon, tick, PlayerInput.BTN_FIRE)
		assert_eq(weapon.ammo_in_mag, 29)
		assert_eq(weapon.reserve_ammo, 150)
	assert_eq(_shots, [0])
	assert_eq(_reload_starts, 1)
	assert_eq(_reload_finishes, 0)
	_step(weapon, 13, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [0, 13])
	assert_eq(_reload_finishes, 1)
	assert_eq(_ammo_events, [Vector2i(30, 150), Vector2i(29, 150),
		Vector2i(30, 149), Vector2i(29, 149)])


func test_empty_reload_uses_longer_duration_and_partial_reserve() -> void:
	var weapon: Weapon = _weapon()
	weapon.ammo_in_mag = 0
	weapon.reserve_ammo = 5
	_step(weapon, 0, PlayerInput.BTN_RELOAD)
	assert_eq(weapon.reload_end_tick, 18)
	_step(weapon, 17, PlayerInput.BTN_FIRE)
	assert_eq(weapon.ammo_in_mag, 0)
	_step(weapon, 18)
	assert_eq(weapon.ammo_in_mag, 5)
	assert_eq(weapon.reserve_ammo, 0)
	assert_eq(_reload_finishes, 1)
	_step(weapon, 19, PlayerInput.BTN_RELOAD)
	assert_eq(_reload_starts, 1)


func test_reload_rejects_full_magazine_and_empty_reserve() -> void:
	var weapon: Weapon = _weapon()
	_step(weapon, 0, PlayerInput.BTN_RELOAD)
	assert_eq(weapon.state, Weapon.State.IDLE)
	_step(weapon, 1)
	weapon.ammo_in_mag = 10
	weapon.reserve_ammo = 0
	_step(weapon, 2, PlayerInput.BTN_RELOAD)
	assert_eq(weapon.state, Weapon.State.IDLE)
	assert_eq(_reload_starts, 0)
	assert_eq(_reload_finishes, 0)


func test_held_reload_does_not_restart_after_completion() -> void:
	var weapon: Weapon = _weapon()
	weapon.ammo_in_mag = 20
	for tick: int in range(40):
		_step(weapon, tick, PlayerInput.BTN_RELOAD | PlayerInput.BTN_FIRE)
	assert_eq(_reload_starts, 1)
	assert_eq(_reload_finishes, 1)
	assert_eq(_shots, [12, 18, 24, 30, 36])


func test_cycle_modes_cancels_burst_and_preserves_cooldown() -> void:
	var weapon: Weapon = _weapon()
	assert_eq(weapon.fire_mode, WeaponData.FireMode.AUTO)
	_step(weapon, 0, PlayerInput.BTN_FIRE)
	assert_true(weapon.cycle_fire_mode())
	assert_eq(weapon.fire_mode, WeaponData.FireMode.SEMI)
	_step(weapon, 6, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [0])
	assert_true(weapon.cycle_fire_mode())
	assert_eq(weapon.fire_mode, WeaponData.FireMode.BURST)
	_step(weapon, 7)
	_step(weapon, 8, PlayerInput.BTN_FIRE)
	assert_eq(weapon.next_fire_tick, 14)
	assert_true(weapon.cycle_fire_mode())
	_step(weapon, 14)
	assert_eq(_shots, [0, 8])
	assert_eq(weapon.fire_mode, WeaponData.FireMode.AUTO)


func test_single_mode_and_busy_states_reject_mode_change() -> void:
	var weapon: Weapon = _weapon()
	weapon.data.fire_modes = [WeaponData.FireMode.AUTO]
	assert_false(weapon.cycle_fire_mode())
	weapon.data.fire_modes = [WeaponData.FireMode.AUTO, WeaponData.FireMode.SEMI]
	weapon.ammo_in_mag = 10
	_step(weapon, 0, PlayerInput.BTN_RELOAD)
	assert_false(weapon.cycle_fire_mode())
	assert_true(weapon.switch_out())
	assert_false(weapon.cycle_fire_mode())
	assert_false(weapon.switch_out())
	assert_false(weapon.switch_in())


func test_blocked_prevents_fire_and_reload_and_consumes_semi_press() -> void:
	var weapon: Weapon = _weapon()
	assert_true(weapon.cycle_fire_mode())
	for tick: int in range(12):
		_step(weapon, tick, PlayerInput.BTN_FIRE | PlayerInput.BTN_RELOAD, true)
		assert_eq(weapon.state, Weapon.State.BLOCKED)
	assert_eq(_shots.size(), 0)
	assert_eq(_reload_starts, 0)
	_step(weapon, 12, PlayerInput.BTN_FIRE)
	assert_eq(weapon.state, Weapon.State.IDLE)
	_step(weapon, 13)
	_step(weapon, 14, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [14])


func test_blocking_cancels_burst_and_preserves_cooldown() -> void:
	var weapon: Weapon = _weapon()
	assert_true(weapon.cycle_fire_mode())
	assert_true(weapon.cycle_fire_mode())
	_step(weapon, 0, PlayerInput.BTN_FIRE)
	_step(weapon, 1, 0, true)
	_step(weapon, 2, PlayerInput.BTN_FIRE)
	assert_eq(weapon.next_fire_tick, 6)
	_step(weapon, 6, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [0])
	_step(weapon, 7)
	_step(weapon, 8, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [0, 8])


func test_reload_completes_while_blocked_without_firing() -> void:
	var weapon: Weapon = _weapon()
	weapon.ammo_in_mag = 10
	_step(weapon, 0, PlayerInput.BTN_RELOAD)
	_step(weapon, 12, PlayerInput.BTN_FIRE, true)
	assert_eq(weapon.state, Weapon.State.BLOCKED)
	assert_eq(weapon.ammo_in_mag, 30)
	assert_eq(_reload_finishes, 1)
	assert_eq(_shots.size(), 0)


func test_switch_out_cancels_reload_and_stays_holstered_until_drawn() -> void:
	var weapon: Weapon = _weapon()
	weapon.ammo_in_mag = 10
	_step(weapon, 0, PlayerInput.BTN_RELOAD)
	assert_true(weapon.switch_out())
	assert_eq(weapon.state, Weapon.State.SWITCHING_OUT)
	assert_eq(weapon.switch_end_tick, 6)
	for tick: int in range(1, 6):
		_step(weapon, tick, PlayerInput.BTN_FIRE)
		assert_eq(weapon.state, Weapon.State.SWITCHING_OUT)
	_step(weapon, 6, PlayerInput.BTN_FIRE)
	assert_eq(weapon.state, Weapon.State.BLOCKED)
	_step(weapon, 20, PlayerInput.BTN_FIRE)
	assert_eq(weapon.state, Weapon.State.BLOCKED)
	assert_eq(weapon.ammo_in_mag, 10)
	assert_eq(_reload_finishes, 0)
	assert_eq(weapon.reload_end_tick, -1)
	assert_true(weapon.switch_in())
	assert_eq(weapon.state, Weapon.State.SWITCHING_IN)
	assert_eq(weapon.switch_end_tick, 26)
	_step(weapon, 25, PlayerInput.BTN_FIRE)
	assert_eq(_shots.size(), 0)
	_step(weapon, 26, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [26])


func test_network_client_cannot_simulate_or_change_modes() -> void:
	var weapon: Weapon = _weapon()
	var client_api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 9), OK)
	client_api.multiplayer_peer = peer
	var path: NodePath = weapon.get_path()
	get_tree().set_multiplayer(client_api, path)
	assert_false(weapon.multiplayer.is_server())
	_step(weapon, 0, PlayerInput.BTN_FIRE)
	assert_false(weapon.cycle_fire_mode())
	assert_false(weapon.switch_out())
	assert_false(weapon.switch_in())
	assert_eq(weapon.ammo_in_mag, 30)
	assert_eq(weapon.state, Weapon.State.IDLE)
	assert_eq(_shots.size(), 0)
	get_tree().set_multiplayer(null, path)
	peer.close()
