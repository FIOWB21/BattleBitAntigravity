extends GadgetTestCase


func _beacon(world: Node3D, owner: int = 12, at: Vector3 = Vector3.ZERO) -> SpawnBeacon:
	var ctx: GadgetContext = GadgetContext.new()
	ctx.spawn_parent = world
	ctx.owner_id = owner
	ctx.team_id = 1
	ctx.squad_id = 1
	ctx.spawn_transform = Transform3D(Basis.IDENTITY, world.global_position + at)
	return Deployable.spawn(load("res://src/gadgets/scenes/spawn_beacon.tscn"), ctx) as SpawnBeacon


func _player(world: Node3D) -> Player:
	var player: Player = make_player(world, "recon", load("res://src/gadgets/data/spawn_beacon.tres"))
	player.position = Vector3(0, 0, 8)
	return player


func _die(player: Player) -> void:
	(player.health_component as HealthComponent).apply_damage(1000.0)
	(player.health_component as HealthComponent).apply_damage(1.0)
	assert_eq(player.life.state, PlayerLife.State.SPAWN_SELECT)


func _floor(world: Node3D) -> void:
	make_box(world, Vector3(0, -0.5, 0), Vector3(30, 1, 30))


func _sync() -> void:
	for frame: int in range(3):
		await get_tree().physics_frame


func test_only_finally_dead_same_team_and_squad_can_spawn() -> void:
	var world: Node3D = make_world()
	var beacon: SpawnBeacon = _beacon(world)
	var player: Player = _player(world)
	assert_false(beacon.can_spawn(player))
	(player.health_component as HealthComponent).apply_damage(1000.0)
	assert_false(beacon.can_spawn(player))
	(player.health_component as HealthComponent).apply_damage(1.0)
	assert_true(beacon.can_spawn(player))
	player.affiliation.squad_id = 2
	assert_false(beacon.can_spawn(player))
	player.affiliation.squad_id = 0
	assert_false(beacon.can_spawn(player))
	player.affiliation.squad_id = 1
	player.affiliation.team_id = 2
	assert_false(beacon.can_spawn(player))
	player.affiliation.team_id = 1
	assert_true(beacon.can_spawn(player))


func test_safe_spawn_restores_health_standing_pose_and_preserves_ammo() -> void:
	var world: Node3D = make_world()
	_floor(world)
	var beacon: SpawnBeacon = _beacon(world)
	var player: Player = _player(world)
	player.inventory.weapon_at(1).ammo_in_mag = 7
	_die(player)
	player.velocity = Vector3(10, -30, 10)
	await _sync()
	assert_true(beacon.try_spawn(player))
	assert_eq(player.life.state, PlayerLife.State.ALIVE)
	assert_eq((player.health_component as HealthComponent).current, 100.0)
	assert_eq(player.velocity, Vector3.ZERO)
	assert_eq(player.stance, PlayerStance.STAND)
	assert_almost_eq(player.global_position, world.global_position + Vector3(1.5, 0.02, 0), 0.001)
	assert_eq(player.inventory.weapon_at(1).ammo_in_mag, 7)
	assert_false(beacon.try_spawn(player))


func test_blocked_first_location_falls_back_to_next_offset() -> void:
	var world: Node3D = make_world()
	_floor(world)
	make_box(world, Vector3(1.5, 2, 0), Vector3(1, 4, 1))
	var beacon: SpawnBeacon = _beacon(world)
	var player: Player = _player(world)
	_die(player)
	await _sync()
	assert_true(beacon.try_spawn(player))
	assert_almost_eq(player.position.x, -1.5, 0.001)


func test_missing_ground_and_all_blocked_do_not_move_or_resurrect() -> void:
	var world: Node3D = make_world()
	var beacon: SpawnBeacon = _beacon(world)
	var player: Player = _player(world)
	_die(player)
	var before: Vector3 = player.global_position
	await _sync()
	assert_false(beacon.try_spawn(player))
	_floor(world)
	make_box(world, Vector3(0, 2, 0), Vector3(8, 4, 8))
	await _sync()
	assert_false(beacon.try_spawn(player))
	assert_eq(player.global_position, before)
	assert_eq(player.life.state, PlayerLife.State.SPAWN_SELECT)
	assert_true((player.health_component as HealthComponent).is_dead)


func test_real_hitbox_damage_destroys_beacon_and_immediately_disables_spawn() -> void:
	var world: Node3D = make_world()
	_floor(world)
	var beacon: SpawnBeacon = _beacon(world)
	var player: Player = _player(world)
	_die(player)
	await _sync()
	var hit: HitResult = HitscanQuery.cast(world.global_position + Vector3(0, 0.5, 2),
		world.global_position + Vector3(0, 0.5, -2), [], world.get_world_3d().direct_space_state)
	assert_eq(hit.health_component, beacon.health)
	hit.hitbox.apply_damage(100.0, 77)
	assert_true(beacon.health.is_dead)
	assert_true(beacon.is_queued_for_deletion())
	assert_false(beacon.try_spawn(player))
	assert_false(beacon.visible)


func test_explosion_can_destroy_beacon_without_player_specific_code() -> void:
	var world: Node3D = make_world()
	var beacon: SpawnBeacon = _beacon(world)
	var explosion: Explosion = Explosion.new()
	world.add_child(explosion)
	await _sync()
	explosion.apply(load("res://src/weapons/projectiles/frag.tres"),
		world.global_position + Vector3(0, 0.5, 1), 3)
	assert_true(beacon.health.is_dead)
	assert_true(beacon.is_queued_for_deletion())


func test_replacement_retires_only_same_owner_in_same_world() -> void:
	var world: Node3D = make_world()
	var first: SpawnBeacon = _beacon(world)
	var other: SpawnBeacon = _beacon(world, 99)
	var second: SpawnBeacon = _beacon(world)
	assert_true(first.is_queued_for_deletion())
	assert_false(first.visible)
	assert_false(other.is_queued_for_deletion())
	assert_false(second.is_queued_for_deletion())
	var foreign_world: Node3D = make_world()
	_beacon(foreign_world)
	assert_false(second.is_queued_for_deletion())
	var player: Player = _player(foreign_world)
	_die(player)
	assert_false(second.can_spawn(player))


func test_client_cannot_respawn_or_destroy_beacon() -> void:
	var world: Node3D = make_world()
	_floor(world)
	var beacon: SpawnBeacon = _beacon(world)
	var player: Player = _player(world)
	_die(player)
	await _sync()
	var peer: ENetMultiplayerPeer = client_api(world)
	assert_false(beacon.try_spawn(player))
	assert_false(player.life.select_beacon_spawn())
	beacon.health.apply_damage(1000.0)
	assert_eq(beacon.health.current, 100.0)
	assert_eq(player.life.state, PlayerLife.State.SPAWN_SELECT)
	restore_api(world, peer)


func test_occupied_player_capsule_forces_another_spawn_position() -> void:
	var world: Node3D = make_world()
	_floor(world)
	var beacon: SpawnBeacon = _beacon(world)
	var player: Player = _player(world)
	var occupant: Player = _player(world)
	occupant.position = Vector3(1.5, 0, 0)
	_die(player)
	await _sync()
	assert_true(beacon.try_spawn(player))
	assert_almost_eq(player.position.x, -1.5, 0.001)


func test_configuration_rejects_invalid_health_offsets_and_probe_geometry() -> void:
	var config: BeaconConfig = load("res://src/gadgets/data/beacon_config.tres").duplicate() as BeaconConfig
	assert_true(config.is_valid())
	for property: StringName in [&"max_health", &"probe_up", &"probe_down", &"floor_margin"]:
		var original: float = config.get(property)
		for invalid: float in [0.0, -1.0, NAN, INF]:
			config.set(property, invalid)
			assert_false(config.is_valid())
		config.set(property, original)
	config.offsets = PackedVector3Array([Vector3(NAN, 0, 0)])
	assert_false(config.is_valid())
	config.offsets = PackedVector3Array()
	assert_false(config.is_valid())


func test_real_deploy_snapshots_server_affiliation() -> void:
	var world: Node3D = make_world()
	_floor(world)
	var player: Player = _player(world)
	player.affiliation.team_id = 3
	player.affiliation.squad_id = 7
	player.inventory.active_slot = 3
	var placed: Array[Deployable] = []
	player.equipment.gadgets.gadget_at(3).deployable_created.connect(
		func(object: Deployable) -> void: placed.append(object))
	await _sync()
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.buttons = PlayerInput.BTN_FIRE
	player.equipment.gadgets.simulate(inp)
	assert_eq(placed.size(), 1)
	assert_eq(placed[0].team_id, 3)
	assert_eq(placed[0].squad_id, 7)
	assert_eq(placed[0].owner_id, player.get_instance_id())


func test_spawn_button_retries_failure_and_reuses_existing_nodes() -> void:
	var world: Node3D = make_world()
	_floor(world)
	var player: Player = _player(world)
	var view: PlayerLifeView = PlayerLifeView.new()
	world.add_child(view)
	view.setup(player.life)
	_die(player)
	view.beacon_button.pressed.emit()
	assert_true(view.beacon_button.text.contains("No safe"))
	_beacon(world)
	await _sync()
	var count: int = get_tree().get_node_count()
	for cycle: int in range(30):
		view.beacon_button.pressed.emit()
		assert_eq(player.life.state, PlayerLife.State.ALIVE)
		_die(player)
	assert_eq(get_tree().get_node_count(), count)
