extends GadgetTestCase


func test_real_floor_wall_and_missing_ground() -> void:
	var world: Node3D = make_world()
	make_box(world, Vector3(0, -0.5, 0), Vector3(20, 1, 20))
	var solver: GroundDeployment = GroundDeployment.new()
	var config: DeploymentConfig = load("res://src/gadgets/data/ground_placement.tres") as DeploymentConfig
	for frame: int in range(3):
		await get_tree().physics_frame
	assert_true(solver.solve(world.get_world_3d().direct_space_state, world.global_position, 0.0, config, []))
	assert_almost_eq(solver.pose.origin, world.global_position + Vector3(0, 0, -1.5), 0.001)
	make_box(world, Vector3(0, 1, -0.75), Vector3(2, 2, 0.2))
	for frame: int in range(3):
		await get_tree().physics_frame
	assert_false(solver.solve(world.get_world_3d().direct_space_state, world.global_position, 0.0, config, []))
	assert_false(solver.solve(world.get_world_3d().direct_space_state,
		world.global_position + Vector3(50, 0, 0), 0.0, config, []))


func test_slot_input_deploys_once_and_death_blocks_action() -> void:
	var world: Node3D = make_world()
	make_box(world, Vector3(0, -0.5, 0), Vector3(20, 1, 20))
	var player: Player = make_player(world, "medic", load("res://src/gadgets/data/medkit.tres"))
	var controller: PlayerGadgets = player.equipment.gadgets
	var gadget: Gadget = controller.gadget_at(Loadout.Slot.GADGET_1)
	assert_not_null(gadget)
	for frame: int in range(3):
		await get_tree().physics_frame
	player.inventory.active_slot = Loadout.Slot.GADGET_1
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.buttons = PlayerInput.BTN_FIRE
	controller.simulate(inp)
	assert_eq(gadget.charges, 0)
	assert_eq(world.get_child_count(), 3)
	inp.tick = 2
	controller.simulate(inp)
	assert_eq(world.get_child_count(), 3)
	inp.tick = 3
	inp.buttons = 0
	controller.simulate(inp)
	(player.health_component as HealthComponent).apply_damage(1000.0)
	inp.tick = 10000
	inp.buttons = PlayerInput.BTN_RELOAD
	controller.simulate(inp)
	assert_eq(gadget.reload_end_tick, -1)


func test_forbidden_class_does_not_create_gadget() -> void:
	var player: Player = make_player(make_world(), "assault", load("res://src/gadgets/data/medkit.tres"))
	assert_null(player.equipment.gadgets.gadget_at(Loadout.Slot.GADGET_1))


func test_profile_validation_rejects_nonfinite_geometry() -> void:
	var config: DeploymentConfig = DeploymentConfig.new()
	config.clearance_size.y = -1.0
	assert_false(config.is_valid())
	config.clearance_size.y = 0.35
	config.probe_down = INF
	assert_false(config.is_valid())
