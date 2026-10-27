extends GutTest

const CATALOG: WeaponCatalog = preload("res://src/weapons/data/balanced_catalog.tres")
const HITBOXES: HitboxConfig = preload("res://src/player/default_hitboxes.tres")


func test_catalog_has_all_seventeen_unique_profiles_and_requested_categories() -> void:
	var counts: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	var ids: Array[StringName] = []
	assert_eq(CATALOG.weapons.size(), 17)
	for data: WeaponData in CATALOG.weapons:
		assert_not_null(data)
		assert_false(data.id.is_empty())
		assert_false(data.display_name.is_empty())
		assert_false(String(data.id).begins_with("sample_"))
		assert_does_not_have(ids, data.id)
		ids.append(data.id)
		counts[data.category] += 1
	assert_eq(counts, [3, 2, 2, 2, 2, 2, 3, 1])


func test_profiles_have_valid_ammo_handling_and_damage_data() -> void:
	for data: WeaponData in CATALOG.weapons:
		assert_gt(data.rpm, 0.0, String(data.id))
		assert_gt(data.mag_size, 0)
		assert_gt(data.reserve_mags, 0)
		assert_gt(data.reload_time, 0.0)
		assert_gte(data.reload_empty_time, data.reload_time)
		assert_gt(data.range_far, data.range_near)
		assert_gt(data.ads_time, 0.0)
		assert_gt(data.move_speed_mult, 0.0)
		assert_gt(data.spread_ads_deg, 0.0)
		assert_gte(data.spread_hip_deg, data.spread_ads_deg)
		assert_false(data.recoil_pattern.is_empty())
		assert_false(data.fire_modes.is_empty())
		assert_has(WeaponData.FireMode.values(), data.fire_modes[0])
		if data.projectile_data == null:
			assert_gt(data.damage_far, 0.0)
			assert_gte(data.damage_near, data.damage_far)
			assert_gt(data.pellets, 0)


func test_assault_rifles_meet_medium_distance_target_at_real_tick_rate() -> void:
	for data: WeaponData in CATALOG.weapons:
		if data.category != WeaponData.Category.AR:
			continue
		for distance: float in [25.0, 50.0]:
			var ttk: float = TtkCalculator.seconds(data, distance, 100.0, HITBOXES.torso_mult, 60)
			assert_gte(ttk, 0.25, String(data.id))
			assert_lte(ttk, 0.4, String(data.id))


func test_smg_close_range_advantage_is_traded_for_weaker_range() -> void:
	for smg: WeaponData in CATALOG.weapons:
		if smg.category != WeaponData.Category.SMG:
			continue
		for rifle: WeaponData in CATALOG.weapons:
			if rifle.category != WeaponData.Category.AR:
				continue
			assert_lt(TtkCalculator.seconds(smg, 5.0, 100.0, 1.0, 60),
				TtkCalculator.seconds(rifle, 5.0, 100.0, 1.0, 60))
			assert_gt(TtkCalculator.seconds(smg, 100.0, 100.0, 1.0, 60),
				TtkCalculator.seconds(rifle, 100.0, 100.0, 1.0, 60))


func test_snipers_kill_with_one_headshot_using_actual_hitbox_multiplier() -> void:
	for data: WeaponData in CATALOG.weapons:
		if data.category != WeaponData.Category.SNIPER:
			continue
		for distance: float in [5.0, 50.0, 200.0, data.hitscan_range]:
			assert_eq(TtkCalculator.shots_to_kill(data, distance, 100.0, HITBOXES.head_mult), 1)
			assert_eq(TtkCalculator.seconds(data, distance, 100.0, HITBOXES.head_mult, 60), 0.0)
			assert_gt(TtkCalculator.shots_to_kill(data, distance, 100.0, HITBOXES.torso_mult), 1)


func test_lmg_supports_sustained_fire_and_stronger_stance_advantage() -> void:
	var rifle: WeaponData = CATALOG.weapons[0]
	for data: WeaponData in CATALOG.weapons:
		if data.category != WeaponData.Category.LMG:
			continue
		assert_gt(data.mag_size, rifle.mag_size * 2)
		assert_gt(data.mag_size * data.cooldown(), rifle.mag_size * rifle.cooldown() * 2.0)
		assert_lt(data.move_speed_mult, rifle.move_speed_mult)
		assert_gt(data.reload_empty_time, rifle.reload_empty_time)
		var handling: WeaponHandling = WeaponHandling.new()
		handling.setup(data)
		var stand: float = handling.spread_degrees(true, PlayerStance.STAND, 0.0)
		assert_lt(handling.spread_degrees(true, PlayerStance.CROUCH, 0.0) / stand, rifle.spread_crouch_mult)
		assert_lt(handling.spread_degrees(true, PlayerStance.PRONE, 0.0) / stand, rifle.spread_prone_mult)


func test_underbarrel_uses_gravity_contact_explosion_and_radial_damage() -> void:
	var weapon: WeaponData = CATALOG.weapons[16]
	var projectile: ProjectileData = weapon.projectile_data
	assert_eq(weapon.category, WeaponData.Category.LAUNCHER)
	assert_eq(weapon.mag_size, 1)
	assert_false(weapon.chamber_enabled)
	assert_not_null(projectile)
	assert_eq(projectile.kind, ProjectileData.Kind.FRAG)
	assert_true(projectile.impact_detonation)
	assert_eq(projectile.collision_mask & HitboxZone.LAYER_HITBOXES, HitboxZone.LAYER_HITBOXES)
	assert_lt(projectile.gravity.y, 0.0)
	assert_gt(projectile.speed, 0.0)
	assert_eq(weapon.damage_near, 0.0)
	assert_almost_eq(projectile.damage_at(0.0), 150.0, 0.0001)
	assert_almost_eq(projectile.damage_at(2.0), 100.0, 0.0001)
	assert_almost_eq(projectile.damage_at(4.0), 50.0, 0.0001)
	assert_eq(projectile.damage_at(6.0), 0.0)
	assert_eq(projectile.damage_at(0.0, false), 0.0)


func test_generated_report_matches_committed_file_and_does_not_mutate_resources() -> void:
	var expected: String = FileAccess.get_file_as_string("res://docs/BALANCE.md")
	var before: float = CATALOG.weapons[0].damage_near
	var actual: String = BalanceReport.generate(CATALOG, HITBOXES, Engine.physics_ticks_per_second)
	assert_eq(actual, expected, "Regenerate docs/BALANCE.md after editing .tres")
	assert_eq(BalanceReport.generate(CATALOG, HITBOXES, Engine.physics_ticks_per_second), actual)
	assert_eq(CATALOG.weapons[0].damage_near, before)
	for data: WeaponData in CATALOG.weapons:
		assert_true(actual.contains(String(data.id)), String(data.id))
