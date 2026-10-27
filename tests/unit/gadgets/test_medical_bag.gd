extends GadgetTestCase


func _bag(world: Node3D) -> MedicalBag:
	var bag: MedicalBag = load("res://src/gadgets/scenes/medical_bag.tscn").instantiate() as MedicalBag
	world.add_child(bag)
	bag.set_physics_process(false)
	return bag


func test_profile_and_class_permission() -> void:
	var profile: GadgetData = load("res://src/gadgets/data/medkit.tres") as GadgetData
	assert_true(profile.is_valid())
	assert_true(profile.placement.is_valid())
	var loadout: Loadout = Loadout.new()
	loadout.gadget_1 = profile
	assert_eq(LoadoutValidator.validate(load("res://src/classes/data/medic.tres"), loadout), [])
	assert_false(LoadoutValidator.validate(load("res://src/classes/data/assault.tres"), loadout).is_empty())


func test_rate_deduplicates_zones_and_caps_health() -> void:
	var world: Node3D = make_world()
	var bag: MedicalBag = _bag(world)
	var health: HealthComponent = make_target(world, Vector3.RIGHT)
	health.apply_damage(50.0)
	bag.aura.track(zone_of(health))
	bag.aura.track(zone_of(health))
	var extra: HitboxZone = HitboxZone.new()
	extra.health_component = health
	health.get_parent().add_child(extra)
	bag.aura.track(extra)
	bag.step(1.0)
	assert_almost_eq(health.current, 60.0, 0.0001)
	bag.aura.untrack(extra)
	bag.step(10.0)
	assert_eq(health.current, 100.0)
	bag.aura.untrack(zone_of(health))
	assert_eq(bag.aura.targets.size(), 0)


func test_spherical_radius_boundary_all_targets_and_movement() -> void:
	var world: Node3D = make_world()
	var bag: MedicalBag = _bag(world)
	for at: Vector3 in [Vector3(4, 0, 0), Vector3(0, 4, 0), Vector3(0, 0, 4.01)]:
		var health: HealthComponent = make_target(world, at)
		health.apply_damage(50.0)
		bag.aura.track(zone_of(health))
		bag.step(1.0)
		assert_eq(health.current, 50.0 if at.z > 4.0 else 60.0)
		(health.get_parent() as Node3D).position = Vector3(8, 0, 0)


func test_dead_and_downed_targets_are_not_revived() -> void:
	var world: Node3D = make_world()
	var bag: MedicalBag = _bag(world)
	var health: HealthComponent = make_target(world, Vector3.ZERO)
	bag.aura.track(zone_of(health))
	health.apply_damage(100.0)
	bag.step(1.0)
	assert_eq(health.current, 0.0)
	health.is_downed = true
	bag.step(1.0)
	assert_true(health.is_downed)
	assert_eq(health.current, 0.0)


func test_exact_lifetime_and_oversized_delta_apply_only_twenty_seconds() -> void:
	var world: Node3D = make_world()
	var bag: MedicalBag = _bag(world)
	var health: HealthComponent = make_target(world, Vector3.ZERO)
	health.max_health = 1000.0
	health.reset()
	health.apply_damage(900.0)
	bag.aura.track(zone_of(health))
	bag.step(19.0)
	assert_false(bag.is_queued_for_deletion())
	assert_almost_eq(health.current, 290.0, 0.001)
	bag.step(100.0)
	assert_true(bag.is_queued_for_deletion())
	assert_almost_eq(health.current, 300.0, 0.001)
	bag.step(1.0)
	assert_almost_eq(health.current, 300.0, 0.001)


func test_invalid_delta_and_deleted_target_are_safe() -> void:
	var world: Node3D = make_world()
	var bag: MedicalBag = _bag(world)
	var health: HealthComponent = make_target(world, Vector3.ZERO)
	bag.aura.track(zone_of(health))
	health.get_parent().free()
	for delta: float in [NAN, INF, -1.0, 0.0]:
		bag.step(delta)
	assert_eq(bag.remaining, 20.0)
	bag.step(1.0)
	assert_eq(bag.remaining, 19.0)


func test_client_cannot_heal_or_advance_lifetime() -> void:
	var world: Node3D = make_world()
	var bag: MedicalBag = _bag(world)
	var health: HealthComponent = make_target(world, Vector3.ZERO)
	health.apply_damage(50.0)
	bag.aura.track(zone_of(health))
	var peer: ENetMultiplayerPeer = client_api(world)
	bag.step(30.0)
	assert_eq(health.current, 50.0)
	assert_eq(bag.remaining, 20.0)
	assert_false(bag.is_queued_for_deletion())
	restore_api(world, peer)


func test_real_area_tracks_and_untracks_target() -> void:
	var world: Node3D = make_world()
	var bag: MedicalBag = _bag(world)
	var health: HealthComponent = make_target(world, Vector3(1, 0, 0))
	health.apply_damage(50.0)
	for frame: int in range(4):
		await get_tree().physics_frame
	assert_eq(bag.aura.targets.size(), 1)
	bag.step(1.0)
	assert_eq(health.current, 60.0)
	(health.get_parent() as Node3D).position = Vector3(10, 0, 0)
	for frame: int in range(4):
		await get_tree().physics_frame
	assert_eq(bag.aura.targets.size(), 0)


func test_invalid_config_is_rejected() -> void:
	var config: MedicalBagConfig = MedicalBagConfig.new()
	assert_true(config.is_valid())
	config.radius = NAN
	assert_false(config.is_valid())
	config.radius = 4.0
	config.heal_per_second = -1.0
	assert_false(config.is_valid())
	config.heal_per_second = 10.0
	config.lifetime = INF
	assert_false(config.is_valid())
