extends GadgetTestCase


func _component(world: Node3D) -> PlayerProjectiles:
	return make_player(world, "medic", load("res://src/gadgets/data/medkit.tres")).equipment.projectiles


func test_three_successful_throws_exhaust_stock_and_supply_restores_capacity() -> void:
	var component: PlayerProjectiles = _component(make_world())
	assert_eq(component.grenades, 3)
	var inp: PlayerInput = PlayerInput.new()
	inp.throw_grenade = true
	for index: int in range(4):
		inp.tick = index * 60 + 1
		component.simulate(inp)
	assert_eq(component.grenades, 0)
	assert_false(component.system.projectiles[3].active)
	assert_eq(component.add_grenades(1), 1)
	assert_eq(component.add_grenades(100), 2)
	assert_eq(component.grenades, 3)
	assert_eq(component.add_grenades(1), 0)
	assert_eq(component.add_grenades(-1), 0)


func test_failed_pool_launch_does_not_spend_grenade() -> void:
	var component: PlayerProjectiles = _component(make_world())
	for index: int in range(component.system.projectiles.size()):
		assert_not_null(component.system.launch(component.profile, Vector3.ZERO, Vector3.ZERO))
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.throw_grenade = true
	component.simulate(inp)
	assert_eq(component.grenades, 3)


func test_client_cannot_throw_or_replenish_stock() -> void:
	var world: Node3D = make_world()
	var component: PlayerProjectiles = _component(world)
	component.grenades = 1
	var peer: ENetMultiplayerPeer = client_api(world)
	assert_eq(component.add_grenades(2), 0)
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.throw_grenade = true
	component.simulate(inp)
	assert_eq(component.grenades, 1)
	assert_false(component.system.projectiles[0].active)
	restore_api(world, peer)


func test_view_tracks_events_and_remote_has_no_counter() -> void:
	var component: PlayerProjectiles = _component(make_world())
	assert_null(component.stock_view)
	var view: GrenadeStockView = GrenadeStockView.new()
	add_child_autofree(view)
	view.setup(component)
	component.grenades = 0
	component.add_grenades(2)
	assert_eq((view.get_child(0) as Label).text, "GRENADES  2 / 3")
	var config: GrenadeStockConfig = GrenadeStockConfig.new()
	config.initial_count = config.capacity + 1
	assert_false(config.is_valid())


func test_missing_stock_disables_supply_and_view_handles_zero_capacity() -> void:
	var component: PlayerProjectiles = _component(make_world())
	component.stock = null
	assert_eq(component.add_grenades(1), 0)
	var view: GrenadeStockView = GrenadeStockView.new()
	add_child_autofree(view)
	view.setup(component)
	assert_eq((view.get_child(0) as Label).text, "GRENADES  3 / 0")
