extends GadgetTestCase


func _target(world: Node3D, team: int = 2, at: Vector3 = Vector3(0, 1.65, -8)) -> CombatAffiliation:
	var health: HealthComponent = make_target(world, at)
	var affiliation: CombatAffiliation = CombatAffiliation.new()
	affiliation.actor = health.get_parent() as Node3D
	affiliation.health = health
	affiliation.team_id = team
	health.get_parent().add_child(affiliation)
	return affiliation


func _registry(world: Node3D, capacity: int = 32) -> SpotRegistry:
	var registry: SpotRegistry = SpotRegistry.new()
	registry.data = load("res://src/gadgets/data/spotting_device.tres").duplicate() as SpottingData
	registry.data.capacity = capacity
	registry.setup(world)
	world.set_meta(&"spot_registry", registry)
	return registry


func _sync() -> void:
	for frame: int in range(3):
		await get_tree().physics_frame


func test_eight_second_boundary_and_refresh_share_one_mark() -> void:
	var world: Node3D = make_world()
	var target: CombatAffiliation = _target(world)
	var registry: SpotRegistry = _registry(world)
	assert_true(registry.spot(target, 1, 8.0))
	registry.step(7.99)
	assert_true(registry.marks[0].is_visible_to(1))
	assert_true(registry.spot(target, 1, 8.0))
	assert_eq(registry.marks[0].remaining, 8.0)
	assert_eq(registry.marks[1].remaining, 0.0)
	registry.step(8.0)
	assert_false(registry.marks[0].is_visible_to(1))
	assert_null(registry.marks[0].target)


func test_only_observer_allies_see_enemy_and_invalid_targets_rejected() -> void:
	var world: Node3D = make_world()
	var target: CombatAffiliation = _target(world)
	var registry: SpotRegistry = _registry(world)
	assert_false(registry.spot(target, 2, 8.0))
	assert_false(registry.spot(target, 0, 8.0))
	assert_false(registry.spot(target, 1, NAN))
	assert_true(registry.spot(target, 1, 8.0))
	assert_true(registry.marks[0].is_visible_to(1))
	assert_false(registry.marks[0].is_visible_to(2))
	assert_false(registry.marks[0].is_visible_to(3))
	target.health.apply_damage(1000.0)
	registry.step(0.01)
	assert_eq(registry.marks[0].remaining, 0.0)


func test_removed_target_and_team_change_clear_marks_safely() -> void:
	var world: Node3D = make_world()
	var registry: SpotRegistry = _registry(world)
	var target: CombatAffiliation = _target(world)
	registry.spot(target, 1, 8.0)
	target.team_id = 1
	registry.step(0.1)
	assert_eq(registry.marks[0].remaining, 0.0)
	target.team_id = 2
	registry.spot(target, 1, 8.0)
	target.actor.free()
	registry.step(0.1)
	assert_eq(registry.marks[0].remaining, 0.0)


func test_pool_rejects_overflow_and_reuses_expired_entries() -> void:
	var world: Node3D = make_world()
	var registry: SpotRegistry = _registry(world, 1)
	var first: CombatAffiliation = _target(world)
	var second: CombatAffiliation = _target(world)
	assert_true(registry.spot(first, 1, 8.0))
	assert_false(registry.spot(second, 1, 8.0))
	registry.step(8.0)
	assert_true(registry.spot(second, 1, 8.0))
	assert_eq(registry.marks.size(), 1)


func test_world_registry_is_shared_and_physics_frame_advances_once() -> void:
	var world: Node3D = make_world()
	var registry: SpotRegistry = SpotRegistry.for_world(world)
	assert_eq(SpotRegistry.for_world(world), registry)
	registry.spot(_target(world), 1, 8.0)
	registry.advance(1.0, 100)
	registry.advance(1.0, 100)
	registry.advance(1.0, 99)
	assert_eq(registry.marks[0].remaining, 7.0)
	registry.advance(1.0, 101)
	assert_eq(registry.marks[0].remaining, 6.0)


func test_plain_health_has_no_affiliation_and_invalid_delta_preserves_deadline() -> void:
	var world: Node3D = make_world()
	assert_null(CombatAffiliation.from_health(make_target(world, Vector3.ZERO)))
	var registry: SpotRegistry = _registry(world)
	registry.spot(_target(world), 1, 8.0)
	registry.step(NAN)
	registry.step(-1.0)
	assert_eq(registry.marks[0].remaining, 8.0)


func test_player_ray_spots_once_while_held_and_preserves_enemy_hp() -> void:
	var world: Node3D = make_world()
	var target: CombatAffiliation = _target(world)
	var player: Player = make_player(world, "recon", load("res://src/gadgets/data/spotting_device.tres"))
	player.inventory.active_slot = 3
	var registry: SpotRegistry = player.equipment.gadgets.spots
	await _sync()
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.buttons = PlayerInput.BTN_FIRE
	player.equipment.gadgets.simulate(inp)
	assert_true(registry.marks[0].is_visible_to(1))
	assert_eq(registry.marks[0].target, target)
	assert_eq(target.health.current, 100.0)
	registry.step(1.0)
	inp.tick = 2
	player.equipment.gadgets.simulate(inp)
	assert_eq(registry.marks[0].remaining, 7.0)
	assert_eq(player.equipment.gadgets.gadget_at(3).charges, 0)


func test_acquisition_wall_range_and_friend_do_not_spend_charge() -> void:
	var world: Node3D = make_world()
	var target: CombatAffiliation = _target(world, 1)
	var player: Player = make_player(world, "recon", load("res://src/gadgets/data/spotting_device.tres"))
	player.inventory.active_slot = 3
	await _sync()
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.buttons = PlayerInput.BTN_FIRE
	player.equipment.gadgets.simulate(inp)
	assert_eq(player.equipment.gadgets.gadget_at(3).charges, 1)
	target.team_id = 2
	var wall: StaticBody3D = make_box(world, Vector3(0, 1.65, -4), Vector3(2, 4, 0.2))
	await _sync()
	_press_again(player, inp, 2)
	assert_eq(player.equipment.gadgets.gadget_at(3).charges, 1)
	wall.free()
	target.actor.position.z = -251.0
	await _sync()
	_press_again(player, inp, 4)
	assert_eq(player.equipment.gadgets.gadget_at(3).charges, 1)


func _press_again(player: Player, inp: PlayerInput, tick: int) -> void:
	inp.buttons = 0
	inp.tick = tick
	player.equipment.gadgets.simulate(inp)
	inp.tick = tick + 1
	inp.buttons = PlayerInput.BTN_FIRE
	player.equipment.gadgets.simulate(inp)


func test_client_cannot_add_refresh_or_expire_marks() -> void:
	var world: Node3D = make_world()
	var target: CombatAffiliation = _target(world)
	var registry: SpotRegistry = _registry(world)
	registry.spot(target, 1, 8.0)
	var peer: ENetMultiplayerPeer = client_api(world)
	assert_false(registry.spot(target, 1, 10.0))
	registry.step(100.0)
	assert_eq(registry.marks[0].remaining, 8.0)
	restore_api(world, peer)


func test_hud_is_visible_through_wall_only_for_allies_and_reuses_labels() -> void:
	var world: Node3D = make_world()
	var target: CombatAffiliation = _target(world)
	var viewer: CombatAffiliation = _target(world, 1, Vector3.ZERO)
	var registry: SpotRegistry = _registry(world)
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	var view: SpotMarkers = SpotMarkers.new()
	world.add_child(view)
	view.setup(registry, viewer, camera)
	make_box(world, Vector3(0, 0, -4), Vector3(4, 8, 0.2))
	registry.spot(target, 1, 8.0)
	var count: int = get_tree().get_node_count()
	for frame: int in range(1200):
		view.update_markers()
	assert_true(view.labels[0].visible)
	assert_eq(get_tree().get_node_count(), count)
	viewer.team_id = 2
	view.update_markers()
	assert_false(view.labels[0].visible)
	viewer.team_id = 1
	registry.step(8.0)
	view.update_markers()
	assert_false(view.labels[0].visible)
