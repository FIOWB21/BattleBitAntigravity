extends GadgetTestCase


func test_preheated_view_updates_without_node_growth_and_hides_with_slot() -> void:
	var world: Node3D = make_world()
	var fixture: RepairFixture = load("res://src/gadgets/scenes/repair_fixture.tscn").instantiate() as RepairFixture
	fixture.position = Vector3(0, 0, -3)
	world.add_child(fixture)
	var tool: RepairTool = RepairTool.new()
	tool.data = load("res://src/gadgets/data/repair_tool.tres") as RepairToolData
	world.add_child(tool)
	tool.setup([])
	var view: RepairToolView = RepairToolView.new()
	world.add_child(view)
	view.setup(tool)
	view.set_active(true)
	for frame: int in range(3):
		await get_tree().physics_frame
	var count: int = get_tree().get_node_count()
	var inp: PlayerInput = PlayerInput.new()
	inp.buttons = PlayerInput.BTN_FIRE
	var aim: Transform3D = Transform3D(Basis.IDENTITY, world.global_position + Vector3(0, 0.6, 0))
	for tick: int in range(1, 1201):
		inp.tick = tick
		tool.simulate(inp, aim, true)
	assert_eq(get_tree().get_node_count(), count)
	view.set_active(false)
	assert_false(view.visible)
	assert_false((view.get_child(1) as CanvasLayer).visible)
	assert_false((view.get_node("RepairToolModel/Beam") as MeshInstance3D).visible)


func test_vertical_beam_and_degenerate_aim_are_safe() -> void:
	var world: Node3D = make_world()
	var tool: RepairTool = RepairTool.new()
	tool.data = load("res://src/gadgets/data/repair_tool.tres") as RepairToolData
	world.add_child(tool)
	tool.setup([])
	var view: RepairToolView = RepairToolView.new()
	world.add_child(view)
	view.setup(tool)
	view.set_active(true)
	tool.presentation_changed.emit(true, world.global_position + Vector3(0.3, 5.0, -0.75), 0.5, false)
	assert_true((view.get_node("RepairToolModel/Beam") as MeshInstance3D).global_transform.is_finite())
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.buttons = PlayerInput.BTN_FIRE
	tool.simulate(inp, Transform3D(Basis.from_scale(Vector3.ZERO), world.global_position), true)
	assert_false(tool.is_repairing)
	assert_eq(tool.heat, 0.0)


func test_dedicated_local_player_creates_no_repair_view() -> void:
	var world: Node3D = make_world()
	var player: Player = load("res://src/player/player.tscn").instantiate() as Player
	player.class_data = load("res://src/classes/data/engineer.tres") as ClassData
	var inventory: Inventory = player.get_node("Inventory") as Inventory
	inventory.loadout = inventory.loadout.duplicate() as Loadout
	inventory.loadout.primary = load("res://src/weapons/data/smg.tres") as WeaponData
	inventory.loadout.gadget_1 = load("res://src/gadgets/data/repair_tool.tres") as GadgetData
	(player.get_node("Weapon") as Weapon).data = inventory.loadout.primary
	var dedicated: bool = Game.is_dedicated
	Game.is_dedicated = true
	world.add_child(player)
	Game.is_dedicated = dedicated
	player.set_physics_process(false)
	player.set_process(false)
	player.release_mouse()
	assert_not_null(player.equipment.gadgets.tool_at(3))
	assert_null(player.equipment.gadgets.tool_at(3).view)
	assert_null(player.equipment.projectiles.stock_view)
