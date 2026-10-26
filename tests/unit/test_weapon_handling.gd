extends GutTest

const EPSILON: float = 0.00001
const TPS: int = 60
const ATTACKER: int = 7


func _data() -> WeaponData:
	var data: WeaponData = WeaponData.new()
	data.recoil_pattern = [Vector2(1.0, 0.2), Vector2(2.0, -0.1)]
	data.recoil_fallback_deg = Vector2(0.8, 0.0)
	data.recoil_noise_deg = Vector2(0.2, 0.3)
	data.recoil_pause = 0.2
	data.recoil_recovery_deg_per_second = 10.0
	data.spread_per_shot_deg = 0.5
	data.spread_max_bloom_deg = 2.0
	data.spread_recovery_deg_per_second = 1.0
	return data


func _handling(data: WeaponData) -> WeaponHandling:
	var handling: WeaponHandling = WeaponHandling.new()
	handling.setup(data)
	return handling


func test_pattern_then_seeded_noise_repeats_across_independent_instances() -> void:
	var data: WeaponData = _data()
	var first: WeaponHandling = _handling(data)
	var second: WeaponHandling = _handling(data)
	for shot: int in range(8):
		var tick: int = shot * 6
		first.advance(tick, TPS)
		second.advance(tick, TPS)
		var previous: Vector2 = first.recoil_deg
		first.apply_shot(tick, ATTACKER)
		second.apply_shot(tick, ATTACKER)
		assert_eq(first.recoil_deg, second.recoil_deg)
		assert_eq(first.bloom_deg, second.bloom_deg)
		var kick: Vector2 = first.recoil_deg - previous
		if shot < 2:
			assert_almost_eq(kick, data.recoil_pattern[shot], EPSILON)
		else:
			assert_between(kick.x, 0.6 - EPSILON, 1.0 + EPSILON)
			assert_between(kick.y, -0.3 - EPSILON, 0.3 + EPSILON)
	assert_eq(data.recoil_pattern, [Vector2(1.0, 0.2), Vector2(2.0, -0.1)])


func test_noise_changes_with_tick_and_attacker_without_spread_rng_coupling() -> void:
	var data: WeaponData = _data()
	data.recoil_pattern = []
	var first: WeaponHandling = _handling(data)
	var second: WeaponHandling = _handling(data)
	first.advance(10, TPS)
	second.advance(10, TPS)
	first.spread_direction(Basis.IDENTITY, 15.0, 10, ATTACKER, 0)
	first.apply_shot(10, ATTACKER)
	second.apply_shot(10, ATTACKER)
	assert_eq(first.recoil_deg, second.recoil_deg)
	second.setup(data)
	second.advance(11, TPS)
	second.apply_shot(11, ATTACKER)
	assert_ne(first.recoil_deg, second.recoil_deg)
	second.setup(data)
	second.advance(10, TPS)
	second.apply_shot(10, ATTACKER + 1)
	assert_ne(first.recoil_deg, second.recoil_deg)


func test_recoil_holds_through_pause_then_recovers_and_pattern_restarts() -> void:
	var handling: WeaponHandling = _handling(_data())
	handling.advance(0, TPS)
	handling.apply_shot(0, ATTACKER)
	var initial: Vector2 = handling.recoil_deg
	handling.advance(12, TPS)
	assert_eq(handling.recoil_deg, initial)
	handling.advance(15, TPS)
	assert_lt(handling.recoil_deg.length(), initial.length())
	assert_gt(handling.recoil_deg.length(), 0.0)
	handling.advance(120, TPS)
	assert_eq(handling.recoil_deg, Vector2.ZERO)
	assert_eq(handling.bloom_deg, 0.0)
	handling.apply_shot(120, ATTACKER)
	assert_eq(handling.recoil_deg, initial)


func test_skipped_ticks_and_per_tick_recovery_match() -> void:
	var first: WeaponHandling = _handling(_data())
	var second: WeaponHandling = _handling(_data())
	first.advance(0, TPS)
	second.advance(0, TPS)
	first.apply_shot(0, ATTACKER)
	second.apply_shot(0, ATTACKER)
	first.advance(15, TPS)
	for tick: int in range(1, 16):
		second.advance(tick, TPS)
	assert_almost_eq(first.recoil_deg, second.recoil_deg, EPSILON)
	assert_almost_eq(first.bloom_deg, second.bloom_deg, EPSILON)


func test_duplicate_old_ticks_and_duplicate_shots_do_not_change_state() -> void:
	var handling: WeaponHandling = _handling(_data())
	handling.advance(20, TPS)
	handling.apply_shot(20, ATTACKER)
	var initial: Vector2 = handling.recoil_deg
	assert_false(handling.advance(20, TPS))
	assert_false(handling.advance(19, TPS))
	handling.apply_shot(20, ATTACKER)
	handling.apply_shot(21, ATTACKER)
	assert_eq(handling.recoil_deg, initial)
	assert_eq(handling.bloom_deg, 0.5)


func test_bloom_grows_to_cap_and_recovers_without_fire() -> void:
	var data: WeaponData = _data()
	data.spread_recovery_deg_per_second = 0.0
	var handling: WeaponHandling = _handling(data)
	for tick: int in range(20):
		handling.advance(tick, TPS)
		handling.apply_shot(tick, ATTACKER)
		assert_lte(handling.bloom_deg, data.spread_max_bloom_deg)
	assert_eq(handling.bloom_deg, 2.0)
	data.spread_recovery_deg_per_second = 1.0
	handling.advance(79, TPS)
	assert_eq(handling.bloom_deg, 1.0)
	handling.advance(139, TPS)
	assert_eq(handling.bloom_deg, 0.0)


func test_movement_increases_spread_and_stances_and_ads_reduce_it() -> void:
	var handling: WeaponHandling = _handling(_data())
	handling.advance(0, TPS)
	handling.apply_shot(0, ATTACKER)
	var standing: float = handling.spread_degrees(false, PlayerStance.STAND, 0.0)
	var moving: float = handling.spread_degrees(false, PlayerStance.STAND, 4.0)
	assert_gt(moving, standing)
	assert_almost_eq(handling.spread_degrees(false, PlayerStance.CROUCH, 4.0), moving * 0.7, EPSILON)
	assert_almost_eq(handling.spread_degrees(false, PlayerStance.PRONE, 4.0), moving * 0.45, EPSILON)
	assert_lt(handling.spread_degrees(true, PlayerStance.STAND, 4.0), moving)
	assert_lt(handling.spread_degrees(true, PlayerStance.PRONE, 4.0),
		handling.spread_degrees(true, PlayerStance.CROUCH, 4.0))


func test_configured_cap_and_zero_spread() -> void:
	var data: WeaponData = _data()
	data.spread_max_deg = 7.0
	var handling: WeaponHandling = _handling(data)
	assert_eq(handling.spread_degrees(false, PlayerStance.STAND, 100.0), 7.0)
	data.spread_max_deg = 0.0
	assert_eq(handling.spread_degrees(false, PlayerStance.STAND, 4.0), 0.0)
	var basis: Basis = Basis.from_euler(Vector3(0.3, 1.2, -0.2))
	assert_almost_eq(handling.spread_direction(basis, 0.0, 42, ATTACKER, 0), -basis.z, EPSILON)


func test_spread_distribution_stays_in_rotated_cones_and_covers_solid_angle() -> void:
	var handling: WeaponHandling = _handling(_data())
	var basis: Basis = Basis.from_euler(Vector3(0.3, 1.2, -0.2))
	for angle: float in [0.3, 5.0, 15.0, 90.0]:
		var sum: Vector3 = Vector3.ZERO
		var sum_cos: float = 0.0
		var cos_limit: float = cos(deg_to_rad(angle))
		for pellet: int in range(2048):
			var direction: Vector3 = handling.spread_direction(basis, angle, 42, ATTACKER, pellet)
			assert_almost_eq(direction.length(), 1.0, EPSILON)
			assert_gte(direction.dot(-basis.z), cos_limit - EPSILON)
			sum += basis.inverse() * direction
			sum_cos += direction.dot(-basis.z)
		assert_almost_eq(sum_cos / 2048.0, (1.0 + cos_limit) * 0.5, 0.015)
		assert_lt(absf(sum.x / 2048.0), 0.03)
		assert_lt(absf(sum.y / 2048.0), 0.03)


func test_directions_repeat_and_change_with_seed_and_pellet() -> void:
	var first: WeaponHandling = _handling(_data())
	var second: WeaponHandling = _handling(_data())
	for pellet: int in range(128):
		var direction: Vector3 = first.spread_direction(Basis.IDENTITY, 5.0, 42, ATTACKER, pellet)
		assert_eq(direction, second.spread_direction(Basis.IDENTITY, 5.0, 42, ATTACKER, pellet))
		assert_ne(direction, second.spread_direction(Basis.IDENTITY, 5.0, 43, ATTACKER, pellet))
		assert_ne(direction, second.spread_direction(Basis.IDENTITY, 5.0, 42, ATTACKER + 1, pellet))
		assert_ne(direction, second.spread_direction(Basis.IDENTITY, 5.0, 42, ATTACKER, pellet + 1))


func test_recoil_clamps_pitch_and_preserves_manual_compensation() -> void:
	var handling: WeaponHandling = _handling(_data())
	handling.recoil_deg = Vector2(5.0, 2.0)
	var rotation: Vector3 = handling.aim_rotation(deg_to_rad(88.0), 0.3, 0.1)
	assert_almost_eq(rotation.x, deg_to_rad(89.0), EPSILON)
	assert_almost_eq(rotation.y, 0.3 + deg_to_rad(2.0), EPSILON)
	assert_almost_eq(rotation.z, 0.1, EPSILON)
	rotation = handling.aim_rotation(deg_to_rad(-5.0), deg_to_rad(-2.0), 0.0)
	assert_almost_eq(rotation, Vector3.ZERO, EPSILON)


func test_setup_clears_state_and_loaded_profiles_store_handling_parameters() -> void:
	var handling: WeaponHandling = _handling(_data())
	handling.advance(0, TPS)
	handling.apply_shot(0, ATTACKER)
	handling.setup(null)
	assert_eq(handling.recoil_deg, Vector2.ZERO)
	assert_eq(handling.bloom_deg, 0.0)
	assert_false(handling.advance(1, TPS))
	assert_eq(handling.spread_degrees(false, PlayerStance.STAND, 4.0), 0.0)
	for profile: String in ["ar", "smg", "lmg", "dmr", "sniper", "shotgun", "pistol", "launcher"]:
		var data: WeaponData = load("res://src/weapons/data/" + profile + ".tres") as WeaponData
		assert_false(data.recoil_pattern.is_empty(), profile)
		assert_gt(data.recoil_recovery_deg_per_second, 0.0, profile)
		assert_gt(data.spread_per_shot_deg, 0.0, profile)
		assert_gt(data.spread_move_deg_per_mps, 0.0, profile)
		assert_between(data.spread_crouch_mult, 0.0, 1.0, profile)
		assert_lt(data.spread_prone_mult, data.spread_crouch_mult, profile)
