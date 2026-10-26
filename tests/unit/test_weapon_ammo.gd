extends GutTest

var _clicks: Array[int] = []
var _cancelled: int = 0
var _finished: int = 0


func before_each() -> void:
	_clicks.clear()
	_cancelled = 0
	_finished = 0


func _weapon() -> Weapon:
	var profile: WeaponData = WeaponData.new()
	profile.reload_time = 0.2
	profile.reload_empty_time = 0.3
	profile.draw_time = 0.1
	profile.rpm = 600.0
	var weapon: Weapon = Weapon.new()
	weapon.data = profile
	weapon.ticks_per_second = 60
	weapon.dry_fired.connect(func(tick: int) -> void: _clicks.append(tick))
	weapon.reload_cancelled.connect(func() -> void: _cancelled += 1)
	weapon.reload_finished.connect(func() -> void: _finished += 1)
	add_child_autofree(weapon)
	return weapon


func _step(weapon: Weapon, tick: int, buttons: int = 0, sprinting: bool = false) -> void:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = tick
	inp.buttons = buttons
	weapon.simulate(inp, sprinting, sprinting)


func test_reload_conserves_ammo_for_all_magazine_and_small_reserve_pairs() -> void:
	var weapon: Weapon = _weapon()
	for chamber: bool in [false, true]:
		weapon.data.chamber_enabled = chamber
		for magazine: int in range(32):
			for reserve: int in range(33):
				weapon.setup(weapon.data)
				weapon.ammo_in_mag = magazine
				weapon.reserve_ammo = reserve
				var capacity: int = 31 if chamber and magazine > 0 else 30
				var moved: int = mini(maxi(capacity - magazine, 0), reserve)
				_step(weapon, 0, PlayerInput.BTN_RELOAD)
				_step(weapon, 100)
				assert_eq(weapon.ammo_in_mag, magazine + moved)
				assert_eq(weapon.reserve_ammo, reserve - moved)
				assert_eq(weapon.ammo_in_mag + weapon.reserve_ammo, magazine + reserve)
	print("ACCEPT 2.5: 2112 reload combinations conserve rounds, including partial reserves")


func test_tactical_reload_at_nominal_full_magazine_adds_chamber_round_once() -> void:
	var weapon: Weapon = _weapon()
	_step(weapon, 0, PlayerInput.BTN_RELOAD)
	assert_eq(weapon.reload_end_tick, 12)
	_step(weapon, 11)
	assert_eq(weapon.ammo_in_mag, 30)
	_step(weapon, 12)
	assert_eq(weapon.ammo_in_mag, 31)
	assert_eq(weapon.reserve_ammo, 149)
	_step(weapon, 13, PlayerInput.BTN_RELOAD)
	assert_eq(weapon.state, Weapon.State.IDLE)
	assert_eq(_finished, 1)


func test_empty_reload_has_no_extra_chamber_and_uses_empty_duration() -> void:
	var weapon: Weapon = _weapon()
	weapon.ammo_in_mag = 0
	_step(weapon, 0, PlayerInput.BTN_RELOAD)
	assert_eq(weapon.reload_end_tick, 18)
	_step(weapon, 17)
	assert_eq(weapon.ammo_in_mag, 0)
	_step(weapon, 18)
	assert_eq(weapon.ammo_in_mag, 30)
	assert_eq(weapon.reserve_ammo, 120)


func test_sprint_cancels_reload_without_transferring_or_restarting_on_held_reload() -> void:
	var weapon: Weapon = _weapon()
	weapon.ammo_in_mag = 7
	_step(weapon, 0, PlayerInput.BTN_RELOAD)
	_step(weapon, 5, PlayerInput.BTN_RELOAD, true)
	assert_eq(weapon.reload_end_tick, -1)
	assert_eq(weapon.state, Weapon.State.BLOCKED)
	_step(weapon, 30, PlayerInput.BTN_RELOAD)
	assert_eq(weapon.ammo_in_mag, 7)
	assert_eq(weapon.reserve_ammo, 150)
	assert_eq(_cancelled, 1)
	assert_eq(_finished, 0)
	_step(weapon, 31)
	_step(weapon, 32, PlayerInput.BTN_RELOAD)
	_step(weapon, 44)
	assert_eq(weapon.ammo_in_mag, 31)
	assert_eq(weapon.reserve_ammo, 126)


func test_sprint_cancellation_setting_preserves_reload_but_blocks_fire() -> void:
	var weapon: Weapon = _weapon()
	weapon.data.reload_interrupt_on_sprint = false
	weapon.ammo_in_mag = 4
	_step(weapon, 0, PlayerInput.BTN_RELOAD)
	_step(weapon, 5, PlayerInput.BTN_FIRE, true)
	assert_eq(weapon.state, Weapon.State.RELOADING)
	_step(weapon, 12, PlayerInput.BTN_FIRE, true)
	assert_eq(weapon.state, Weapon.State.BLOCKED)
	assert_eq(weapon.ammo_in_mag, 31)
	assert_eq(_cancelled, 0)
	assert_eq(_finished, 1)


func test_switch_setting_rejects_switch_until_reload_finishes() -> void:
	var weapon: Weapon = _weapon()
	weapon.data.reload_interrupt_on_switch = false
	weapon.ammo_in_mag = 4
	_step(weapon, 0, PlayerInput.BTN_RELOAD)
	assert_false(weapon.switch_out())
	assert_eq(weapon.reload_end_tick, 12)
	_step(weapon, 12)
	assert_true(weapon.switch_out())
	assert_eq(weapon.ammo_in_mag, 31)
	assert_eq(_cancelled, 0)


func test_switch_cancelled_reload_does_not_complete_after_drawing_again() -> void:
	var weapon: Weapon = _weapon()
	weapon.ammo_in_mag = 0
	_step(weapon, 0, PlayerInput.BTN_RELOAD)
	assert_true(weapon.switch_out())
	_step(weapon, 6)
	assert_true(weapon.switch_in())
	_step(weapon, 100)
	assert_eq(weapon.ammo_in_mag, 0)
	assert_eq(weapon.reserve_ammo, 150)
	assert_eq(_cancelled, 1)
	assert_eq(_finished, 0)


func test_empty_trigger_clicks_once_per_press_in_every_fire_mode() -> void:
	var weapon: Weapon = _weapon()
	for mode: WeaponData.FireMode in [WeaponData.FireMode.AUTO, WeaponData.FireMode.SEMI,
			WeaponData.FireMode.BURST]:
		weapon.setup(weapon.data)
		weapon.fire_mode = mode
		weapon.ammo_in_mag = 0
		_clicks.clear()
		for tick: int in range(30):
			_step(weapon, tick, PlayerInput.BTN_FIRE)
		assert_eq(_clicks, [0])
		_step(weapon, 30)
		_step(weapon, 31, PlayerInput.BTN_FIRE)
		_step(weapon, 31, PlayerInput.BTN_FIRE)
		assert_eq(_clicks, [0, 31])
		assert_eq(weapon.reserve_ammo, 150)


func test_empty_click_is_suppressed_when_blocked_reloading_or_switching() -> void:
	var weapon: Weapon = _weapon()
	weapon.ammo_in_mag = 0
	_step(weapon, 0, PlayerInput.BTN_FIRE, true)
	_step(weapon, 1, PlayerInput.BTN_RELOAD)
	_step(weapon, 2, PlayerInput.BTN_FIRE)
	assert_true(weapon.switch_out())
	_step(weapon, 3)
	_step(weapon, 4, PlayerInput.BTN_FIRE)
	assert_eq(_clicks.size(), 0)


func test_invalid_magazine_and_reserve_configuration_cannot_create_ammo() -> void:
	var weapon: Weapon = _weapon()
	weapon.data.mag_size = 0
	weapon.setup(weapon.data)
	_step(weapon, 0, PlayerInput.BTN_RELOAD)
	assert_eq(weapon.state, Weapon.State.IDLE)
	assert_eq(weapon.ammo_in_mag, 0)
	assert_eq(weapon.reserve_capacity(), 0)
	weapon.data.mag_size = -2
	weapon.data.reserve_mags = -3
	weapon.setup(weapon.data)
	assert_eq(weapon.ammo_in_mag, 0)
	assert_eq(weapon.reserve_ammo, 0)
	assert_eq(weapon.add_reserve_ammo(100), 0)
