extends GutTest

const EPSILON: float = 0.00001
const DELTA: float = 1.0 / 60.0

var _ads: WeaponAds
var _data: WeaponData
var _inp: PlayerInput


func before_each() -> void:
	_ads = WeaponAds.new()
	_data = WeaponData.new()
	_data.ads_time = 0.2
	_ads.setup(_data)
	_inp = PlayerInput.new()
	_inp.buttons = PlayerInput.BTN_AIM


func _step(delta: float = DELTA) -> void:
	_inp.tick += 1
	_ads.simulate(_inp, delta)
	_ads.update_visuals(delta)


func test_ads_reaches_endpoint_at_ads_time_and_returns_in_same_time() -> void:
	for tick: int in range(11):
		_step()
		assert_lt(_ads.fraction, 1.0)
		assert_lt(_ads.visual_fraction, 1.0)
	_step()
	assert_almost_eq(_ads.fraction, 1.0, EPSILON)
	assert_almost_eq(_ads.fov(90.0), 67.5, EPSILON)
	_inp.buttons = 0
	for tick: int in range(12):
		_step()
	assert_almost_eq(_ads.fraction, 0.0, EPSILON)
	assert_almost_eq(_ads.fov(90.0), 90.0, EPSILON)


func test_visual_fov_is_continuous_independent_of_tick_rate() -> void:
	_ads.simulate(_inp, DELTA)
	assert_eq(_ads.fov(90.0), 90.0, "Input tick must not jump rendered FOV")
	var previous: float = 90.0
	for frame: int in range(144):
		_ads.update_visuals(_data.ads_time / 144.0)
		var current: float = _ads.fov(90.0)
		assert_lte(current, previous)
		assert_lt(absf(current - previous), 0.25)
		previous = current
	assert_almost_eq(previous, 67.5, EPSILON)
	_ads.update_visuals(1.0)
	assert_almost_eq(_ads.fov(90.0), 67.5, EPSILON)


func test_reversal_starts_at_current_fov_and_retains_progress() -> void:
	_step(0.08)
	var previous: float = _ads.fov(90.0)
	_inp.buttons = 0
	_step(0.0)
	assert_eq(_ads.fov(90.0), previous)
	_step(0.04)
	assert_almost_eq(_ads.fraction, 0.2, EPSILON)
	assert_gt(_ads.fov(90.0), previous)
	_inp.buttons = PlayerInput.BTN_AIM
	_step(0.16)
	assert_almost_eq(_ads.fraction, 1.0, EPSILON)


func test_sensitivity_is_inverse_perspective_zoom_for_all_base_fovs() -> void:
	assert_almost_eq(WeaponAds.sensitivity_scale(90.0, 90.0), 1.0, EPSILON)
	assert_almost_eq(WeaponAds.sensitivity_scale(60.0, 90.0), 1.0 / sqrt(3.0), EPSILON)
	for base: float in [60.0, 90.0, 120.0]:
		for multiplier: float in [0.4, 0.75, 1.0]:
			var aimed: float = base * multiplier
			var scale: float = WeaponAds.sensitivity_scale(aimed, base)
			var zoom: float = tan(deg_to_rad(base) / 2.0) / tan(deg_to_rad(aimed) / 2.0)
			assert_almost_eq(scale * zoom, 1.0, EPSILON)
	var reader: LocalInputReader = LocalInputReader.new()
	reader.aim_sensitivity_scale = WeaponAds.sensitivity_scale(60.0, 90.0)
	reader.apply_mouse_delta(Vector2(10.0, -10.0), 0.2, false)
	assert_almost_eq(reader.pitch, deg_to_rad(2.0 / sqrt(3.0)), EPSILON)
	assert_almost_eq(reader.yaw, -reader.pitch, EPSILON)
	reader.pitch = 0.0
	reader.apply_mouse_delta(Vector2(0.0, -10.0), 0.2, true)
	assert_lt(reader.pitch, 0.0)


func test_movement_blends_weapon_and_ads_multipliers_without_mutating_data() -> void:
	_data.move_speed_mult = 0.9
	_data.ads_move_speed_mult = 0.5
	assert_almost_eq(_ads.movement_multiplier(), 0.9, EPSILON)
	_step(0.1)
	assert_almost_eq(_ads.movement_multiplier(), 0.675, EPSILON)
	_step(0.1)
	assert_almost_eq(_ads.movement_multiplier(), 0.45, EPSILON)
	assert_eq(_data.move_speed_mult, 0.9)
	assert_eq(_data.ads_move_speed_mult, 0.5)


func test_old_ticks_are_ignored_and_disallowed_aim_exits_smoothly() -> void:
	_step(0.1)
	_ads.simulate(_inp, 0.1)
	assert_almost_eq(_ads.fraction, 0.5, EPSILON)
	_inp.tick -= 1
	_ads.simulate(_inp, 1.0)
	assert_almost_eq(_ads.fraction, 0.5, EPSILON)
	_inp.tick += 2
	_ads.simulate(_inp, 0.05, false)
	assert_eq(_ads.target, 0.0)
	assert_almost_eq(_ads.fraction, 0.25, EPSILON)


func test_zero_duration_null_data_and_reset_have_defined_behavior() -> void:
	_data.ads_time = 0.0
	_step(0.0)
	assert_eq(_ads.fraction, 1.0)
	assert_eq(_ads.visual_fraction, 1.0)
	_ads.setup(null)
	_step()
	assert_eq(_ads.fraction, 0.0)
	assert_eq(_ads.visual_fraction, 0.0)
	assert_eq(_ads.fov(90.0), 90.0)
	assert_eq(_ads.movement_multiplier(), 1.0)


func test_profiles_reach_their_own_fov_and_duration() -> void:
	for name: String in ["ar", "smg", "lmg", "dmr", "sniper", "shotgun", "pistol", "launcher"]:
		var data: WeaponData = load("res://src/weapons/data/" + name + ".tres") as WeaponData
		_ads.setup(data)
		_inp.tick += 1
		_ads.simulate(_inp, data.ads_time * 0.5)
		_ads.update_visuals(data.ads_time * 0.5)
		assert_almost_eq(_ads.fraction, 0.5, EPSILON, name)
		assert_gt(_ads.fov(90.0), 90.0 * data.ads_fov_mult, name)
		_inp.tick += 1
		_ads.simulate(_inp, data.ads_time * 0.5)
		_ads.update_visuals(data.ads_time * 0.5)
		assert_almost_eq(_ads.fov(90.0), 90.0 * data.ads_fov_mult, EPSILON, name)
