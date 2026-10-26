extends GutTest

var _shots: Array[int] = []


func before_each() -> void:
	_shots.clear()


func _weapon(mode: WeaponData.FireMode) -> Weapon:
	var profile: WeaponData = load("res://src/weapons/data/ar.tres").duplicate() as WeaponData
	profile.rpm = 600.0
	profile.fire_modes = [mode]
	var weapon: Weapon = Weapon.new()
	weapon.data = profile
	weapon.ticks_per_second = 60
	weapon.fired.connect(_on_fired)
	add_child_autofree(weapon)
	return weapon


func _on_fired(tick: int) -> void:
	_shots.append(tick)


func _step(weapon: Weapon, tick: int, buttons: int) -> void:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = tick
	inp.buttons = buttons
	weapon.simulate(inp)


func test_auto_600_rpm_fires_exactly_ten_times_in_sixty_ticks() -> void:
	var weapon: Weapon = _weapon(WeaponData.FireMode.AUTO)
	for tick: int in range(60):
		_step(weapon, tick, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [0, 6, 12, 18, 24, 30, 36, 42, 48, 54])
	assert_eq(weapon.ammo_in_mag, 20)
	assert_eq(weapon.next_fire_tick, 60)


func test_semi_requires_release_before_each_shot() -> void:
	var weapon: Weapon = _weapon(WeaponData.FireMode.SEMI)
	for tick: int in range(60):
		_step(weapon, tick, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [0])
	_step(weapon, 60, 0)
	_step(weapon, 61, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [0, 61])


func test_semi_does_not_queue_presses_during_cooldown() -> void:
	var weapon: Weapon = _weapon(WeaponData.FireMode.SEMI)
	_step(weapon, 0, PlayerInput.BTN_FIRE)
	_step(weapon, 1, 0)
	for tick: int in range(2, 12):
		_step(weapon, tick, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [0])
	_step(weapon, 12, 0)
	_step(weapon, 13, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [0, 13])


func test_burst_fires_three_and_requires_release() -> void:
	var weapon: Weapon = _weapon(WeaponData.FireMode.BURST)
	for tick: int in range(60):
		_step(weapon, tick, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [0, 6, 12])
	_step(weapon, 60, 0)
	for tick: int in range(61, 80):
		_step(weapon, tick, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [0, 6, 12, 61, 67, 73])


func test_burst_finishes_after_trigger_release() -> void:
	var weapon: Weapon = _weapon(WeaponData.FireMode.BURST)
	_step(weapon, 0, PlayerInput.BTN_FIRE)
	for tick: int in range(1, 30):
		_step(weapon, tick, 0)
	assert_eq(_shots, [0, 6, 12])
	assert_eq(weapon.state, Weapon.State.IDLE)


func test_burst_uses_resource_count_and_stops_at_empty_magazine() -> void:
	var weapon: Weapon = _weapon(WeaponData.FireMode.BURST)
	weapon.data.burst_count = 4
	weapon.ammo_in_mag = 2
	for tick: int in range(30):
		_step(weapon, tick, PlayerInput.BTN_FIRE)
	assert_eq(_shots, [0, 6])
	assert_eq(weapon.ammo_in_mag, 0)
	assert_eq(weapon.reserve_ammo, 150)


func test_duplicate_and_older_ticks_do_not_repeat_actions() -> void:
	var weapon: Weapon = _weapon(WeaponData.FireMode.AUTO)
	_step(weapon, 12, PlayerInput.BTN_FIRE)
	_step(weapon, 12, 0)
	_step(weapon, 0, PlayerInput.BTN_RELOAD)
	assert_eq(_shots, [12])
	assert_eq(weapon.next_fire_tick, 18)
	assert_eq(weapon.state, Weapon.State.FIRING)


func test_tick_rate_and_non_integral_cooldown_round_up() -> void:
	var weapon: Weapon = _weapon(WeaponData.FireMode.AUTO)
	weapon.ticks_per_second = 120
	_step(weapon, 0, PlayerInput.BTN_FIRE)
	assert_eq(weapon.next_fire_tick, 12)
	weapon.data.rpm = 700.0
	_step(weapon, 12, PlayerInput.BTN_FIRE)
	assert_eq(weapon.next_fire_tick, 23)


func test_same_input_produces_identical_state_and_signals() -> void:
	var first: Weapon = _weapon(WeaponData.FireMode.AUTO)
	var second: Weapon = _weapon(WeaponData.FireMode.AUTO)
	var second_shots: Array[int] = []
	second.fired.disconnect(_on_fired)
	second.fired.connect(func(tick: int) -> void: second_shots.append(tick))
	for tick: int in range(240):
		var buttons: int = PlayerInput.BTN_FIRE
		if tick == 40:
			buttons |= PlayerInput.BTN_RELOAD
		var inp: PlayerInput = PlayerInput.new()
		inp.tick = tick
		inp.buttons = buttons
		first.simulate(inp, tick >= 200)
		second.simulate(inp, tick >= 200)
		assert_eq(first.state, second.state)
		assert_eq(first.ammo_in_mag, second.ammo_in_mag)
		assert_eq(first.reserve_ammo, second.reserve_ammo)
		assert_eq(first.next_fire_tick, second.next_fire_tick)
		assert_eq(first.reload_end_tick, second.reload_end_tick)
	assert_eq(_shots, second_shots)
