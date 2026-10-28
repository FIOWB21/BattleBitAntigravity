extends GutTest

var _weapon: Weapon
var _input: PlayerInput


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_weapon = Weapon.new()
	_weapon.data = WeaponData.new()
	_weapon.data.rpm = 600.0
	_weapon.data.mag_size = 3
	_weapon.data.reserve_mags = 1
	_weapon.data.reload_empty_time = 0.5
	_weapon.data.draw_time = 0.5
	add_child_autofree(_weapon)
	_input = PlayerInput.new()


func _advance(tick: int, blocked: bool = false) -> void:
	_input.tick = tick
	_weapon.simulate(_input, blocked)


func test_request_requires_current_server_tick_and_rpm_limits_shots() -> void:
	_advance(100)
	assert_false(_weapon.fire_requested(99))
	assert_false(_weapon.fire_requested(101))
	assert_true(_weapon.fire_requested(100))
	assert_false(_weapon.fire_requested(100))
	for tick: int in range(101, 106):
		_advance(tick)
		assert_false(_weapon.fire_requested(tick))
	_advance(106)
	assert_true(_weapon.fire_requested(106))
	assert_eq(_weapon.ammo_in_mag, 1)


func test_server_empty_magazine_cannot_be_bypassed_by_request_flood() -> void:
	var shots: int = 0
	for tick: int in range(120):
		_advance(tick)
		for request: int in range(5):
			if _weapon.fire_requested(tick):
				shots += 1
	assert_eq(shots, 3)
	assert_eq(_weapon.ammo_in_mag, 0)
	assert_eq(_weapon.reserve_ammo, 3)


func test_reload_blocks_requests_until_server_timer_and_uses_reserve() -> void:
	for tick: int in [0, 6, 12]:
		_advance(tick)
		assert_true(_weapon.fire_requested(tick))
	_input.buttons = PlayerInput.BTN_RELOAD
	_advance(13)
	_input.buttons = 0
	assert_eq(_weapon.state, Weapon.State.RELOADING)
	for tick: int in range(14, 43):
		_advance(tick)
		assert_false(_weapon.fire_requested(tick))
	_advance(43)
	assert_true(_weapon.fire_requested(43))
	assert_eq(_weapon.ammo_in_mag, 2)
	assert_eq(_weapon.reserve_ammo, 0)


func test_blocking_holstering_and_drawing_reject_requests() -> void:
	_advance(100, true)
	assert_false(_weapon.fire_requested(100))
	_advance(101)
	assert_true(_weapon.switch_out())
	assert_false(_weapon.fire_requested(101))
	_advance(131)
	assert_false(_weapon.fire_requested(131))
	assert_true(_weapon.switch_in())
	assert_false(_weapon.fire_requested(131))
	_advance(161)
	assert_true(_weapon.fire_requested(161))


func test_cosmetic_entry_point_cannot_run_on_server() -> void:
	_input.tick = 100
	_input.buttons = PlayerInput.BTN_FIRE
	_weapon.simulate_cosmetic(_input, false, false)
	assert_eq(_weapon.ammo_in_mag, 3)
