extends GadgetTestCase


func _crate(world: Node3D, owner: int = 7) -> AmmoCrate:
	var ctx: GadgetContext = GadgetContext.new()
	ctx.owner_id = owner
	ctx.source_id = 1
	ctx.spawn_parent = world
	ctx.spawn_transform = world.global_transform
	var crate: AmmoCrate = Deployable.spawn(load("res://src/gadgets/scenes/ammo_crate.tscn"), ctx) as AmmoCrate
	crate.set_physics_process(false)
	return crate


func _player(world: Node3D) -> Player:
	return make_player(world, "support", load("res://src/gadgets/data/ammo_box.tres"))


func _track(crate: AmmoCrate, player: Player) -> void:
	for node: Node in player.hitboxes.get_children():
		if node is HitboxZone:
			crate.aura.track(node as HitboxZone)


func test_supply_all_weapons_and_grenades_without_touching_magazines() -> void:
	var world: Node3D = make_world()
	var player: Player = _player(world)
	var crate: AmmoCrate = _crate(world)
	_track(crate, player)
	var secondary: Weapon = player.inventory.weapon_at(Loadout.Slot.SECONDARY)
	player.weapon.reserve_ammo = 0
	secondary.reserve_ammo = 0
	player.equipment.projectiles.grenades = 0
	var magazine: int = player.weapon.ammo_in_mag
	crate.step(0.99)
	assert_eq(player.weapon.reserve_ammo, 0)
	crate.step(0.01)
	assert_eq(player.weapon.reserve_ammo, floori(player.weapon.reserve_capacity() * 0.2))
	assert_eq(secondary.reserve_ammo, floori(secondary.reserve_capacity() * 0.2))
	assert_eq(player.equipment.projectiles.grenades, 1)
	assert_eq(player.weapon.ammo_in_mag, magazine)
	crate.step(100.0)
	assert_eq(player.weapon.reserve_ammo, player.weapon.reserve_capacity())
	assert_eq(secondary.reserve_ammo, secondary.reserve_capacity())
	assert_eq(player.equipment.projectiles.grenades, 3)
	assert_eq(player.weapon.ammo_in_mag, magazine)


func test_new_crate_retires_same_owner_only_and_cannot_supply_after_retirement() -> void:
	var world: Node3D = make_world()
	var first: AmmoCrate = _crate(world, 7)
	var other: AmmoCrate = _crate(world, 8)
	var second: AmmoCrate = _crate(world, 7)
	assert_true(first.is_queued_for_deletion())
	assert_false(first.visible)
	assert_false(other.is_queued_for_deletion())
	assert_false(second.is_queued_for_deletion())
	var player: Player = _player(world)
	player.weapon.reserve_ammo = 0
	_track(first, player)
	first.step(1.0)
	assert_eq(player.weapon.reserve_ammo, 0)
	_track(second, player)
	second.step(1.0)
	assert_gt(player.weapon.reserve_ammo, 0)


func test_owner_registry_is_scoped_to_world_and_freeing_owner_is_safe() -> void:
	var world: Node3D = make_world()
	var first: AmmoCrate = _crate(world)
	var other_world: Node3D = make_world()
	var other: AmmoCrate = _crate(other_world)
	assert_false(first.is_queued_for_deletion())
	assert_false(other.is_queued_for_deletion())
	var player: Player = _player(world)
	_track(first, player)
	player.free()
	first.step(1.0)
	assert_eq(first.aura.targets.size(), 0)


func test_outside_radius_and_dead_or_downed_players_receive_nothing() -> void:
	var world: Node3D = make_world()
	var crate: AmmoCrate = _crate(world)
	var player: Player = _player(world)
	_track(crate, player)
	player.weapon.reserve_ammo = 0
	player.equipment.projectiles.grenades = 0
	player.position.x = 4.01
	crate.step(1.0)
	assert_eq(player.weapon.reserve_ammo, 0)
	player.position.x = 4.0
	crate.step(1.0)
	assert_gt(player.weapon.reserve_ammo, 0)
	player.weapon.reserve_ammo = 0
	player.equipment.projectiles.grenades = 0
	(player.health_component as HealthComponent).apply_damage(1000.0)
	crate.step(1.0)
	assert_eq(player.weapon.reserve_ammo, 0)
	assert_eq(player.equipment.projectiles.grenades, 0)


func test_client_and_invalid_delta_cannot_supply() -> void:
	var world: Node3D = make_world()
	var crate: AmmoCrate = _crate(world)
	var player: Player = _player(world)
	_track(crate, player)
	player.weapon.reserve_ammo = 0
	for delta: float in [NAN, INF, -1.0, 0.0]:
		crate.step(delta)
	assert_eq(player.weapon.reserve_ammo, 0)
	var peer: ENetMultiplayerPeer = client_api(world)
	crate.step(10.0)
	assert_eq(player.weapon.reserve_ammo, 0)
	restore_api(world, peer)
	crate.step(1.0)
	assert_gt(player.weapon.reserve_ammo, 0)


func test_repeated_replacements_have_bounded_nodes() -> void:
	var world: Node3D = make_world()
	_crate(world)
	var count: int = world.get_tree().get_node_count()
	for iteration: int in range(30):
		_crate(world)
		await get_tree().process_frame
		assert_eq(world.get_tree().get_node_count(), count)


func test_support_slot_creates_gadget_and_sets_entity_owner() -> void:
	var world: Node3D = make_world()
	make_box(world, Vector3(0, -0.5, 0), Vector3(20, 1, 20))
	var player: Player = _player(world)
	var gadget: Gadget = player.equipment.gadgets.gadget_at(3)
	assert_not_null(gadget)
	for frame: int in range(3):
		await get_tree().physics_frame
	player.inventory.active_slot = 3
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.buttons = PlayerInput.BTN_FIRE
	player.equipment.gadgets.simulate(inp)
	var crate: AmmoCrate = world.get_child(world.get_child_count() - 1) as AmmoCrate
	assert_not_null(crate)
	assert_eq(crate.owner_id, player.get_instance_id())
	assert_eq(gadget.charges, 0)


func test_invalid_config() -> void:
	var config: AmmoCrateConfig = AmmoCrateConfig.new()
	assert_true(config.is_valid())
	config.interval = 0.0
	assert_false(config.is_valid())
	config.interval = 1.0
	config.ammo_fraction = INF
	assert_false(config.is_valid())
