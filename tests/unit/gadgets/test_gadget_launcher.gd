extends GadgetTestCase


func _player(world: Node3D) -> Player:
	return make_player(world, "assault", load("res://src/gadgets/data/underslung_launcher.tres"))


func _command(player: Player, tick: int, buttons: int = PlayerInput.BTN_FIRE) -> void:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = tick
	inp.buttons = buttons
	player.equipment.gadgets.simulate(inp)


func _active_count(system: ProjectileSystem) -> int:
	var count: int = 0
	for projectile: Projectile in system.projectiles:
		if projectile.active:
			count += 1
	return count


func _sync() -> void:
	for frame: int in range(3):
		await get_tree().physics_frame


func test_slot_launches_existing_contact_projectile_and_separate_charge() -> void:
	var player: Player = _player(make_world())
	var primary: Weapon = player.inventory.weapon_at(1)
	var ammo: int = primary.ammo_in_mag
	var grenades: int = player.equipment.projectiles.grenades
	player.inventory.active_slot = 3
	_command(player, 1)
	var system: ProjectileSystem = player.equipment.projectiles.system
	assert_eq(_active_count(system), 1)
	assert_eq(system.projectiles[0].data, load("res://src/weapons/projectiles/underslung_grenade.tres"))
	assert_almost_eq(system.projectiles[0].velocity, Vector3(0, 0, -60), 0.001)
	assert_eq(system.projectiles[0].global_position, player.head.global_position)
	assert_eq(system.projectiles[0].attacker, player.get_multiplayer_authority())
	assert_eq(primary.ammo_in_mag, ammo)
	assert_eq(player.equipment.projectiles.grenades, grenades)
	assert_eq(player.equipment.gadgets.gadget_at(3).charges, 0)


func test_no_instant_damage_then_real_contact_explosion_damages_target() -> void:
	var world: Node3D = make_world()
	var target: HealthComponent = make_target(world, Vector3(0, 1.65, -5))
	var player: Player = _player(world)
	player.inventory.active_slot = 3
	await _sync()
	_command(player, 1)
	assert_eq(target.current, 100.0)
	player.equipment.projectiles.system.advance(0.1)
	assert_true(target.is_dead)
	assert_eq(_active_count(player.equipment.projectiles.system), 0)


func test_full_shared_pool_rejects_launch_without_spending_charge() -> void:
	var player: Player = _player(make_world())
	var system: ProjectileSystem = player.equipment.projectiles.system
	for projectile: Projectile in system.projectiles:
		projectile.active = true
	player.inventory.active_slot = 3
	_command(player, 1)
	assert_eq(player.equipment.gadgets.gadget_at(3).charges, 1)
	assert_eq(_active_count(system), system.capacity)
	system.projectiles[0].active = false
	_command(player, 2, 0)
	_command(player, 3)
	assert_eq(player.equipment.gadgets.gadget_at(3).charges, 0)


func test_reload_exact_three_second_boundary_and_hold_does_not_repeat() -> void:
	var player: Player = _player(make_world())
	player.inventory.active_slot = 3
	var gadget: Gadget = player.equipment.gadgets.gadget_at(3)
	_command(player, 1)
	_command(player, 2, PlayerInput.BTN_RELOAD)
	assert_eq(gadget.reload_end_tick, 182)
	_command(player, 181, 0)
	assert_eq(gadget.charges, 0)
	_command(player, 182)
	assert_eq(_active_count(player.equipment.projectiles.system), 2)
	_command(player, 1000)
	assert_eq(_active_count(player.equipment.projectiles.system), 2)
	_command(player, 999)
	assert_eq(_active_count(player.equipment.projectiles.system), 2)


func test_weapon_slot_switching_sprint_melee_and_death_block_fire() -> void:
	var player: Player = _player(make_world())
	_command(player, 1)
	assert_eq(_active_count(player.equipment.projectiles.system), 0)
	player.inventory.active_slot = 3
	player.inventory.phase = Inventory.Phase.DRAWING
	_command(player, 2, 0)
	_command(player, 3)
	player.inventory.phase = Inventory.Phase.READY
	player.motor.is_sprinting = true
	_command(player, 4, 0)
	_command(player, 5)
	player.motor.is_sprinting = false
	player.equipment.melee.busy = true
	_command(player, 6, 0)
	_command(player, 7)
	player.equipment.melee.busy = false
	(player.health_component as HealthComponent).apply_damage(1000.0)
	_command(player, 8, 0)
	_command(player, 9)
	assert_eq(_active_count(player.equipment.projectiles.system), 0)
	assert_eq(player.equipment.gadgets.gadget_at(3).charges, 1)


func test_client_cannot_launch_or_spend_charge() -> void:
	var world: Node3D = make_world()
	var player: Player = _player(world)
	player.inventory.active_slot = 3
	var gadget: Gadget = player.equipment.gadgets.gadget_at(3)
	gadget.simulate(1)
	var peer: ENetMultiplayerPeer = client_api(world)
	var ctx: GadgetContext = GadgetContext.new()
	ctx.tick = 1
	assert_false(player.equipment.gadgets.launcher.fire(gadget, ctx, player.head.global_transform,
		player.equipment.projectiles.system, []))
	_command(player, 1)
	assert_eq(_active_count(player.equipment.projectiles.system), 0)
	assert_eq(player.equipment.gadgets.gadget_at(3).charges, 1)
	restore_api(world, peer)


func test_reentrant_launch_event_cannot_duplicate_projectile_or_charge() -> void:
	var player: Player = _player(make_world())
	var gadget: Gadget = player.equipment.gadgets.gadget_at(3)
	gadget.simulate(1)
	var ctx: GadgetContext = GadgetContext.new()
	ctx.tick = 1
	var system: ProjectileSystem = player.equipment.projectiles.system
	var launcher: GadgetLauncher = player.equipment.gadgets.launcher
	var nested: Array[bool] = []
	system.launched.connect(func(_projectile: Projectile) -> void:
		nested.append(launcher.fire(gadget, ctx, player.head.global_transform, system, [])))
	assert_true(launcher.fire(gadget, ctx, player.head.global_transform, system, []))
	assert_eq(nested, [false])
	assert_eq(_active_count(system), 1)
	assert_eq(gadget.charges, 0)


func test_stale_context_invalid_profile_and_aim_never_launch() -> void:
	var player: Player = _player(make_world())
	var gadget: Gadget = player.equipment.gadgets.gadget_at(3)
	gadget.simulate(10)
	var ctx: GadgetContext = GadgetContext.new()
	ctx.tick = 9
	var launcher: GadgetLauncher = player.equipment.gadgets.launcher
	var system: ProjectileSystem = player.equipment.projectiles.system
	assert_false(launcher.fire(gadget, ctx, player.head.global_transform, system, []))
	ctx.tick = 10
	assert_false(launcher.fire(gadget, ctx, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO), system, []))
	var profile: LauncherGadgetData = gadget.data.duplicate() as LauncherGadgetData
	profile.projectile = profile.projectile.duplicate() as ProjectileData
	profile.projectile.speed = NAN
	gadget.data = profile
	assert_false(profile.is_valid())
	assert_false(launcher.fire(gadget, ctx, player.head.global_transform, system, []))
	assert_eq(_active_count(system), 0)
	assert_eq(gadget.charges, 1)


func test_repeated_shots_and_reloads_reuse_projectile_pool() -> void:
	var player: Player = _player(make_world())
	player.inventory.active_slot = 3
	var count: int = get_tree().get_node_count()
	for cycle: int in range(100):
		var tick: int = cycle * 200 + 1
		_command(player, tick)
		assert_eq(_active_count(player.equipment.projectiles.system), 1)
		player.equipment.projectiles.system.advance(6.0)
		_command(player, tick + 1, PlayerInput.BTN_RELOAD)
		_command(player, tick + 181, 0)
	assert_eq(get_tree().get_node_count(), count)


func test_other_class_rejects_assault_launcher() -> void:
	var player: Player = make_player(make_world(), "recon", load("res://src/gadgets/data/underslung_launcher.tres"))
	assert_null(player.equipment.gadgets.gadget_at(3))


func test_charge_hud_tracks_reload_and_slot_without_cosmetic_damage() -> void:
	var world: Node3D = make_world()
	var player: Player = _player(world)
	var view: LauncherStockView = LauncherStockView.new()
	world.add_child(view)
	view.setup(player)
	assert_false(view.visible)
	player.inventory.active_slot = 3
	player.inventory.active_slot_changed.emit(3, null)
	assert_true(view.visible)
	assert_true(view.label.text.contains("1 / 1"))
	_command(player, 1)
	assert_true(view.label.text.contains("0 / 1"))
	_command(player, 2, PlayerInput.BTN_RELOAD)
	assert_true(view.label.text.contains("RELOADING"))
	_command(player, 182, 0)
	assert_true(view.label.text.contains("1 / 1"))
	player.inventory.active_slot_changed.emit(1, player.inventory.weapon_at(1))
	assert_false(view.visible)
