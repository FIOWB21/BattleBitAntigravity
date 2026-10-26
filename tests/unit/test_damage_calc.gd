extends GutTest

const EPSILON: float = 0.00001


func _zone(kind: int, multiplier: float) -> HitboxZone:
	var zone: HitboxZone = HitboxZone.new()
	zone.configure(kind, multiplier, null)
	autofree(zone)
	return zone


func test_zone_multipliers_and_distance_falloff() -> void:
	var data: WeaponData = load("res://src/weapons/data/ar.tres") as WeaponData
	var config: HitboxConfig = load("res://src/player/default_hitboxes.tres") as HitboxConfig
	for kind: int in [HitboxZone.HEAD, HitboxZone.TORSO, HitboxZone.ARMS, HitboxZone.LEGS]:
		var multiplier: float = config.multiplier_for(kind)
		var zone: HitboxZone = _zone(kind, multiplier)
		assert_almost_eq(DamageCalc.compute(data, 10.0, zone), 30.0 * multiplier, EPSILON)
		assert_almost_eq(DamageCalc.compute(data, 52.5, zone), 24.0 * multiplier, EPSILON)
		assert_almost_eq(DamageCalc.compute(data, 200.0, zone), 18.0 * multiplier, EPSILON)


func test_compute_is_repeatable_and_does_not_mutate_inputs() -> void:
	var data: WeaponData = WeaponData.new()
	data.headshot_mult = 9.0
	var zone: HitboxZone = _zone(HitboxZone.HEAD, 2.5)
	var health: HealthComponent = HealthComponent.new()
	autofree(health)
	zone.health_component = health
	for _i: int in range(10):
		assert_almost_eq(DamageCalc.compute(data, 10.0, zone), 75.0, EPSILON)
	assert_eq(health.current, 100.0)
	assert_eq(data.damage_near, 30.0)
	assert_eq(zone.damage_mult, 2.5)


func test_missing_zone_and_non_positive_damage_are_safe() -> void:
	var data: WeaponData = WeaponData.new()
	var zone: HitboxZone = _zone(HitboxZone.TORSO, 1.0)
	assert_eq(DamageCalc.compute(null, 10.0, zone), 0.0)
	assert_eq(DamageCalc.compute(data, 10.0, null), 0.0)
	assert_eq(DamageCalc.compute(data, -10.0, zone), 30.0)
	zone.zone = HitboxZone.NONE
	assert_eq(DamageCalc.compute(data, 10.0, zone), 0.0)
	zone.zone = HitboxZone.TORSO
	zone.damage_mult = -1.0
	assert_eq(DamageCalc.compute(data, 10.0, zone), 0.0)
	zone.damage_mult = 1.0
	data.damage_near = -10.0
	assert_eq(DamageCalc.compute(data, 10.0, zone), 0.0)


func test_shotgun_total_is_sum_of_individual_pellets() -> void:
	var data: WeaponData = load("res://src/weapons/data/shotgun.tres") as WeaponData
	var torso: HitboxZone = _zone(HitboxZone.TORSO, 1.0)
	var total: float = 0.0
	for _pellet: int in range(data.pellets):
		total += DamageCalc.compute(data, 5.0, torso)
	assert_almost_eq(total, 96.0, EPSILON)
