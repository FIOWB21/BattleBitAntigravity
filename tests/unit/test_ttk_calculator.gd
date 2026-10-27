extends GutTest

const CATALOG: WeaponCatalog = preload("res://src/weapons/data/balanced_catalog.tres")
const EPSILON: float = 0.00001


func test_first_shot_time_and_tick_rounding() -> void:
	var data: WeaponData = WeaponData.new()
	data.rpm = 700.0
	assert_eq(TtkCalculator.interval_ticks(data, 60), 6)
	assert_eq(TtkCalculator.shots_to_kill(data, 10.0, 100.0, 1.0), 4)
	assert_almost_eq(TtkCalculator.seconds(data, 10.0, 100.0, 1.0, 60), 0.3, EPSILON)
	assert_almost_eq(TtkCalculator.seconds(data, 10.0, 30.0, 1.0, 60), 0.0, EPSILON)
	assert_eq(TtkCalculator.interval_ticks(data, 120), 11)


func test_pellets_are_one_shot_and_boundary_damage_is_not_truncated() -> void:
	var data: WeaponData = WeaponData.new()
	data.pellets = 8
	data.damage_near = 12.5
	assert_eq(TtkCalculator.shots_to_kill(data, 5.0, 100.0, 1.0), 1)
	assert_eq(TtkCalculator.seconds(data, 5.0, 100.0, 1.0, 60), 0.0)
	data.damage_near = 12.49
	assert_eq(TtkCalculator.shots_to_kill(data, 5.0, 100.0, 1.0), 2)


func test_invalid_unreachable_and_explosive_scenarios_have_no_hitscan_ttk() -> void:
	var data: WeaponData = WeaponData.new()
	for distance: float in [-1.0, INF, NAN, data.hitscan_range + 1.0]:
		assert_eq(TtkCalculator.shots_to_kill(data, distance, 100.0, 1.0), 0)
	assert_eq(TtkCalculator.shots_to_kill(null, 5.0, 100.0, 1.0), 0)
	assert_eq(TtkCalculator.shots_to_kill(data, 5.0, 0.0, 1.0), 0)
	assert_eq(TtkCalculator.shots_to_kill(data, 5.0, INF, 1.0), 0)
	assert_eq(TtkCalculator.shots_to_kill(data, 5.0, 100.0, -1.0), 0)
	assert_eq(TtkCalculator.shots_to_kill(data, 5.0, 100.0, NAN), 0)
	assert_gt(TtkCalculator.shots_to_kill(data, data.hitscan_range, 100.0, 1.0), 0)
	data.projectile_data = ProjectileData.new()
	assert_eq(TtkCalculator.seconds(data, 5.0, 100.0, 1.0, 60), INF)


func test_invalid_rate_empty_modes_and_magazine_do_not_report_a_kill() -> void:
	var data: WeaponData = WeaponData.new()
	for rpm: float in [0.0, -1.0, INF, NAN]:
		data.rpm = rpm
		assert_eq(TtkCalculator.seconds(data, 5.0, 100.0, 1.0, 60), INF)
	data.rpm = 600.0
	assert_eq(TtkCalculator.interval_ticks(data, 0), 0)
	data.mag_size = 3
	assert_eq(TtkCalculator.seconds(data, 5.0, 100.0, 1.0, 60), INF)
	data.mag_size = 30
	data.fire_modes = []
	assert_eq(TtkCalculator.seconds(data, 5.0, 100.0, 1.0, 60), INF)


func test_semi_requires_release_tick_and_burst_retrigger_is_explicitly_excluded() -> void:
	var data: WeaponData = WeaponData.new()
	data.rpm = 6000.0
	data.fire_modes = [WeaponData.FireMode.SEMI]
	assert_eq(TtkCalculator.interval_ticks(data, 60), 2)
	assert_almost_eq(TtkCalculator.seconds(data, 5.0, 100.0, 1.0, 60), 0.1, EPSILON)
	data.fire_modes = [WeaponData.FireMode.BURST]
	data.burst_count = 3
	assert_eq(TtkCalculator.seconds(data, 5.0, 100.0, 1.0, 60), INF)
	assert_almost_eq(TtkCalculator.seconds(data, 5.0, 60.0, 1.0, 60), 1.0 / 60.0, EPSILON)


func test_report_timing_matches_real_weapon_damage_and_health_for_every_hitscan() -> void:
	for data: WeaponData in CATALOG.weapons:
		if data.projectile_data != null:
			continue
		for distance: float in [5.0, 50.0, 200.0]:
			_verify_simulation(data, distance, 1.0)
			_verify_simulation(data, distance, 2.0)


func _verify_simulation(data: WeaponData, distance: float, multiplier: float) -> void:
	var weapon: Weapon = Weapon.new()
	weapon.data = data
	weapon.ticks_per_second = 60
	add_child_autofree(weapon)
	var health: HealthComponent = HealthComponent.new()
	add_child_autofree(health)
	var zone: HitboxZone = HitboxZone.new()
	autofree(zone)
	zone.zone = HitboxZone.TORSO
	zone.damage_mult = multiplier
	weapon.fired.connect(func(_tick: int) -> void:
		health.apply_damage(DamageCalc.compute(data, distance, zone) * data.pellets, 42, zone.zone))
	var expected: float = TtkCalculator.seconds(data, distance, health.max_health, multiplier, 60)
	assert_true(is_finite(expected), String(data.id))
	var inp: PlayerInput = PlayerInput.new()
	var interval: int = TtkCalculator.interval_ticks(data, 60)
	var kill_tick: int = -1
	for tick: int in range(roundi(expected * 60.0) + 2):
		inp.tick = tick
		var fire: bool = data.fire_modes[0] == WeaponData.FireMode.AUTO or tick % interval == 0
		inp.buttons = PlayerInput.BTN_FIRE if fire else 0
		weapon.simulate(inp)
		if health.is_dead:
			kill_tick = tick
			break
	assert_eq(kill_tick, roundi(expected * 60.0), String(data.id))
	assert_eq(data.mag_size - weapon.ammo_in_mag,
		TtkCalculator.shots_to_kill(data, distance, health.max_health, multiplier), String(data.id))
