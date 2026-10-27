extends GadgetTestCase


func _charge(world: Node3D, id: String = "c4", owner: int = 12) -> ExplosiveCharge:
	var ctx: GadgetContext = GadgetContext.new()
	ctx.spawn_parent = world
	ctx.spawn_transform = world.global_transform
	ctx.source_id = 77
	ctx.owner_id = owner
	var charge: ExplosiveCharge = Deployable.spawn(load("res://src/gadgets/scenes/" + id + ".tscn"), ctx) as ExplosiveCharge
	charge.set_physics_process(false)
	charge.config = charge.config.duplicate() as ChargeConfig
	charge.config.blast_offset = Vector3.ZERO
	return charge


func _vehicle(world: Node3D, at: Vector3) -> HealthComponent:
	var health: HealthComponent = make_target(world, at)
	health.max_health = 1000.0
	health.reset()
	for index: int in range(2):
		var surface: RepairSurface = RepairSurface.new()
		surface.health = health
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: SphereShape3D = SphereShape3D.new()
		shape.radius = 0.2
		collision.shape = shape
		surface.add_child(collision)
		health.get_parent().add_child(surface)
	return health


func _sync() -> void:
	for frame: int in range(3):
		await get_tree().physics_frame


func test_blast_radial_falloff_vehicle_times_three_and_deduplication() -> void:
	var world: Node3D = make_world()
	var person: HealthComponent = make_target(world, Vector3(3, 0, 0))
	var vehicle: HealthComponent = _vehicle(world, Vector3(-3, 0, 0))
	var charge: ExplosiveCharge = _charge(world)
	await _sync()
	charge.step(1.0)
	assert_true(charge.detonate(12))
	assert_almost_eq(person.current, 25.0, 0.01)
	assert_almost_eq(vehicle.current, 775.0, 0.01)
	assert_false(charge.detonate(12))
	assert_almost_eq(vehicle.current, 775.0, 0.01)


func test_arming_owner_and_radius_boundaries() -> void:
	var world: Node3D = make_world()
	var outside: HealthComponent = make_target(world, Vector3(6.1, 0, 0))
	var charge: ExplosiveCharge = _charge(world)
	await _sync()
	charge.step(0.99)
	assert_false(charge.detonate(12))
	charge.step(0.01)
	assert_true(charge.armed)
	assert_false(charge.detonate(99))
	assert_true(charge.detonate(12))
	assert_eq(outside.current, 100.0)


func test_wall_blocks_people_and_vehicle_damage() -> void:
	var world: Node3D = make_world()
	var person: HealthComponent = make_target(world, Vector3(0, 0, -3))
	var vehicle: HealthComponent = _vehicle(world, Vector3(0, 0, -4))
	make_box(world, Vector3(0, 0, -1.5), Vector3(4, 4, 0.2))
	var charge: ExplosiveCharge = _charge(world)
	await _sync()
	charge.step(1.0)
	charge.detonate(12)
	assert_eq(person.current, 100.0)
	assert_eq(vehicle.current, 1000.0)


func test_mine_triggers_on_vehicle_after_arming_not_person() -> void:
	var world: Node3D = make_world()
	make_target(world, Vector3(0.5, 0, 0))
	var charge: ExplosiveCharge = _charge(world, "mine")
	await _sync()
	charge.step(1.0)
	assert_false(charge.is_queued_for_deletion())
	var vehicle: HealthComponent = _vehicle(world, Vector3(0.8, 0, 0))
	await _sync()
	charge.step(0.01)
	assert_true(charge.is_queued_for_deletion())
	assert_lt(vehicle.current, 1000.0)


func test_c4_does_not_auto_trigger_and_invalid_delta_does_not_arm() -> void:
	var world: Node3D = make_world()
	_vehicle(world, Vector3(0.8, 0, 0))
	var charge: ExplosiveCharge = _charge(world)
	await _sync()
	charge.step(NAN)
	charge.step(-1.0)
	assert_false(charge.armed)
	charge.step(2.0)
	assert_false(charge.is_queued_for_deletion())
	assert_true(charge.detonate(12))


func test_client_cannot_arm_detonate_or_apply_blast() -> void:
	var world: Node3D = make_world()
	var person: HealthComponent = make_target(world, Vector3(1, 0, 0))
	var charge: ExplosiveCharge = _charge(world)
	charge.step(1.0)
	await _sync()
	var peer: ENetMultiplayerPeer = client_api(world)
	charge.step(1.0)
	assert_false(charge.detonate(12))
	charge.blast.apply(charge.config, world.global_position, 77)
	assert_eq(person.current, 100.0)
	restore_api(world, peer)


func test_controller_only_detonates_own_charges_and_limits_live_objects() -> void:
	var world: Node3D = make_world()
	var control: ChargeControl = ChargeControl.new()
	world.add_child(control)
	var other: ExplosiveCharge = _charge(world, "c4", 99)
	other.step(1.0)
	control.track(other)
	var latest: ExplosiveCharge
	for index: int in range(5):
		latest = _charge(world)
		latest.step(1.0)
		control.track(latest)
	assert_false(other.is_queued_for_deletion())
	control.detonate(99)
	assert_true(other.is_queued_for_deletion())
	assert_false(latest.is_queued_for_deletion())
	control.detonate(12)
	assert_true(latest.is_queued_for_deletion())
	control.detonate(12)
	assert_true(latest.is_queued_for_deletion())


func test_player_input_deploys_once_and_rmb_detonates_after_arming() -> void:
	var world: Node3D = make_world()
	make_box(world, Vector3(0, -0.5, 0), Vector3(20, 1, 20))
	var player: Player = make_player(world, "engineer", load("res://src/gadgets/data/c4.tres"))
	player.inventory.active_slot = 3
	await _sync()
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.buttons = PlayerInput.BTN_FIRE
	var placed: Array[Deployable] = []
	var gadget: Gadget = player.equipment.gadgets.gadget_at(3)
	gadget.deployable_created.connect(func(object: Deployable) -> void: placed.append(object))
	player.equipment.gadgets.simulate(inp)
	assert_eq(placed.size(), 1)
	assert_eq(gadget.charges, 1)
	inp.tick = 2
	player.equipment.gadgets.simulate(inp)
	assert_eq(placed.size(), 1)
	(placed[0] as ExplosiveCharge).step(1.0)
	inp.tick = 3
	inp.buttons = PlayerInput.BTN_AIM
	player.equipment.gadgets.simulate(inp)
	assert_true(placed[0].is_queued_for_deletion())
	assert_eq(gadget.charges, 1)
