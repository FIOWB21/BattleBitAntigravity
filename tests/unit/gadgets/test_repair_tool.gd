extends GadgetTestCase

var _starts: int = 0
var _finishes: int = 0


func before_each() -> void:
	_starts = 0
	_finishes = 0


func _fixture(world: Node3D, at: Vector3 = Vector3(0, 0, -3)) -> RepairFixture:
	var fixture: RepairFixture = load("res://src/gadgets/scenes/repair_fixture.tscn").instantiate() as RepairFixture
	fixture.position = at
	world.add_child(fixture)
	return fixture


func _tool(world: Node3D) -> RepairTool:
	var tool: RepairTool = RepairTool.new()
	tool.data = load("res://src/gadgets/data/repair_tool.tres") as RepairToolData
	tool.overheat_started.connect(func() -> void: _starts += 1)
	tool.overheat_finished.connect(func() -> void: _finishes += 1)
	world.add_child(tool)
	tool.setup([])
	return tool


func _aim(world: Node3D) -> Transform3D:
	return Transform3D(Basis.IDENTITY, world.global_position + Vector3(0, 0.6, 0))


func _command(tick: int, fire: bool = true) -> PlayerInput:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = tick
	inp.buttons = PlayerInput.BTN_FIRE if fire else 0
	return inp


func _sync() -> void:
	for frame: int in range(3):
		await get_tree().physics_frame


func test_one_second_repairs_twenty_five_hp_and_heats_quarter() -> void:
	var world: Node3D = make_world()
	var fixture: RepairFixture = _fixture(world)
	var tool: RepairTool = _tool(world)
	await _sync()
	for tick: int in range(1, 61):
		tool.simulate(_command(tick), _aim(world), true)
	assert_almost_eq(fixture.health.current, 325.0, 0.001)
	assert_almost_eq(tool.heat, 0.25, 0.0001)
	assert_true(tool.is_repairing)
	assert_false(tool.overheated)


func test_overheat_exact_boundary_locks_and_resumes_after_cooling() -> void:
	var world: Node3D = make_world()
	var fixture: RepairFixture = _fixture(world)
	var tool: RepairTool = _tool(world)
	await _sync()
	for tick: int in range(1, 240):
		tool.simulate(_command(tick), _aim(world), true)
	assert_false(tool.overheated)
	tool.simulate(_command(240), _aim(world), true)
	assert_true(tool.overheated)
	assert_eq(tool.heat, 1.0)
	assert_almost_eq(fixture.health.current, 400.0, 0.01)
	assert_eq(_starts, 1)
	for tick: int in range(241, 435):
		tool.simulate(_command(tick), _aim(world), true)
	assert_true(tool.overheated)
	assert_almost_eq(fixture.health.current, 400.0, 0.01)
	tool.simulate(_command(435), _aim(world), true)
	assert_false(tool.overheated)
	assert_eq(_finishes, 1)
	tool.simulate(_command(436), _aim(world), true)
	assert_gt(fixture.health.current, 400.0)


func test_wall_and_reach_block_real_ray() -> void:
	var world: Node3D = make_world()
	var fixture: RepairFixture = _fixture(world, Vector3(0, 0, -5.99))
	var tool: RepairTool = _tool(world)
	await _sync()
	tool.simulate(_command(1), _aim(world), true)
	assert_gt(fixture.health.current, 300.0)
	var before: float = fixture.health.current
	fixture.position.z = -6.01
	await _sync()
	tool.simulate(_command(2), _aim(world), true)
	assert_eq(fixture.health.current, before)
	fixture.position.z = -3.0
	make_box(world, Vector3(0, 0.6, -0.5), Vector3(3, 2, 0.1))
	await _sync()
	tool.simulate(_command(3), _aim(world), true)
	assert_eq(fixture.health.current, before)


func test_full_destroyed_and_nonvehicle_targets_are_not_repaired() -> void:
	var world: Node3D = make_world()
	var fixture: RepairFixture = _fixture(world)
	var tool: RepairTool = _tool(world)
	await _sync()
	fixture.health.reset()
	tool.simulate(_command(1), _aim(world), true)
	assert_eq(tool.heat, 0.0)
	fixture.health.apply_damage(1000.0)
	tool.simulate(_command(2), _aim(world), true)
	assert_eq(fixture.health.current, 0.0)
	fixture.free()
	var health: HealthComponent = make_target(world, Vector3(0, 0.6, -2))
	health.apply_damage(50.0)
	await _sync()
	tool.simulate(_command(3), _aim(world), true)
	assert_eq(health.current, 50.0)
	assert_eq(tool.heat, 0.0)


func test_repeat_old_and_skipped_ticks_do_not_repeat_or_backfill_repair() -> void:
	var world: Node3D = make_world()
	var fixture: RepairFixture = _fixture(world)
	var tool: RepairTool = _tool(world)
	await _sync()
	tool.simulate(_command(10), _aim(world), true)
	var before: float = fixture.health.current
	tool.simulate(_command(10), _aim(world), true)
	tool.simulate(_command(9), _aim(world), true)
	assert_eq(fixture.health.current, before)
	tool.simulate(_command(10000), _aim(world), true)
	assert_almost_eq(fixture.health.current - before, 25.0 / 60.0, 0.001)
	assert_almost_eq(tool.heat, 0.25 / 60.0, 0.0001)


func test_blocked_or_released_tool_cools_without_repairing() -> void:
	var world: Node3D = make_world()
	var fixture: RepairFixture = _fixture(world)
	var tool: RepairTool = _tool(world)
	await _sync()
	for tick: int in range(1, 61):
		tool.simulate(_command(tick), _aim(world), true)
	var before: float = fixture.health.current
	for tick: int in range(61, 91):
		tool.simulate(_command(tick, false), _aim(world), true)
	for tick: int in range(91, 121):
		tool.simulate(_command(tick), _aim(world), false)
	assert_eq(fixture.health.current, before)
	assert_almost_eq(tool.heat, 0.05, 0.0001)
	assert_false(tool.is_repairing)


func test_last_partial_hp_only_heats_for_actual_repair() -> void:
	var world: Node3D = make_world()
	var fixture: RepairFixture = _fixture(world)
	var tool: RepairTool = _tool(world)
	await _sync()
	fixture.health.reset()
	fixture.health.apply_damage(0.1)
	tool.simulate(_command(1), _aim(world), true)
	assert_eq(fixture.health.current, 500.0)
	assert_almost_eq(tool.heat, 0.001, 0.00001)
	tool.simulate(_command(2), _aim(world), true)
	assert_eq(fixture.health.current, 500.0)
	assert_eq(tool.heat, 0.0)


func test_client_cannot_repair_heat_or_mutate_surface() -> void:
	var world: Node3D = make_world()
	var fixture: RepairFixture = _fixture(world)
	var tool: RepairTool = _tool(world)
	await _sync()
	var peer: ENetMultiplayerPeer = client_api(world)
	tool.simulate(_command(1), _aim(world), true)
	assert_eq(fixture.health.current, 300.0)
	assert_eq(tool.heat, 0.0)
	assert_eq((fixture.get_node("Surface") as RepairSurface).repair(100.0), 0.0)
	restore_api(world, peer)


func test_invalid_data_and_deleted_surface_are_safe() -> void:
	var world: Node3D = make_world()
	var fixture: RepairFixture = _fixture(world)
	var tool: RepairTool = _tool(world)
	await _sync()
	fixture.free()
	await _sync()
	tool.simulate(_command(1), _aim(world), true)
	assert_eq(tool.heat, 0.0)
	var config: RepairToolData = tool.data.duplicate() as RepairToolData
	tool.data = config
	config.heat_per_second = NAN
	assert_false(config.is_valid())
	tool.simulate(_command(2), _aim(world), true)
	assert_eq(tool.heat, 0.0)
	config.heat_per_second = 0.25
	config.resume_heat = 1.0
	assert_false(config.is_valid())


func test_player_slot_switch_and_death_block_continuous_repair() -> void:
	var world: Node3D = make_world()
	var fixture: RepairFixture = _fixture(world, Vector3(0, 0, -3))
	var player: Player = make_player(world, "engineer", load("res://src/gadgets/data/repair_tool.tres"))
	var controller: PlayerGadgets = player.equipment.gadgets
	assert_not_null(controller.tool_at(3))
	assert_null(controller.tool_at(3).view)
	await _sync()
	var inp: PlayerInput = _command(1)
	controller.simulate(inp)
	assert_eq(fixture.health.current, 300.0)
	player.inventory.active_slot = 3
	inp.tick = 2
	controller.simulate(inp)
	assert_gt(fixture.health.current, 300.0)
	var before: float = fixture.health.current
	(player.health_component as HealthComponent).apply_damage(1000.0)
	inp.tick = 3
	controller.simulate(inp)
	assert_eq(fixture.health.current, before)
	assert_false(controller.tool_at(3).is_repairing)
