extends GutTest

const PLAYER_SCENE_PATH: String = "res://src/player/player.tscn"
const TESTBED_SCENE_PATH: String = "res://src/maps/testbed/testbed.tscn"
const DEFAULT_MOVEMENT_PATH: String = "res://src/player/default_movement.tres"
const TICK_DELTA: float = 1.0 / 60.0


class MockHealthComponent extends Node:
	var health: float = 100.0
	var last_damage: float = 0.0
	var hit_count: int = 0

	func take_damage(amount: float) -> void:
		last_damage = amount
		health = maxf(0.0, health - amount)
		hit_count += 1


func _create_test_arena() -> Node3D:
	var arena: Node3D = Node3D.new()
	_add_static_box(arena, "Floor", Vector3(100.0, 1.0, 100.0), Vector3(0.0, -0.5, 0.0))
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	var player: Player = packed.instantiate() as Player
	player.name = "Player"
	player.is_local_player = false
	player.position = Vector3(0.0, 0.05, 0.0)
	player.movement_config = (player.movement_config as MovementConfig).duplicate() as MovementConfig
	arena.add_child(player)
	return arena


func _add_static_box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	parent.add_child(body)
	return body


func _settle_player(tree: SceneTree, player: Player) -> void:
	var idle_inp: PlayerInput = PlayerInput.new()
	for _i: int in range(15):
		await tree.physics_frame
		player.step_simulation(idle_inp, TICK_DELTA)
		if player.is_on_floor() and absf(player.velocity.y) < 0.001:
			break


func _step_ticks(tree: SceneTree, player: Player, inp: PlayerInput, ticks: int) -> void:
	for _i: int in range(ticks):
		await tree.physics_frame
		player.step_simulation(inp, TICK_DELTA)


func test_movement_config_step_fall_coyote_and_stamina_defaults() -> void:
	var cfg: MovementConfig = load(DEFAULT_MOVEMENT_PATH) as MovementConfig
	assert_not_null(cfg, "default_movement.tres must load")
	assert_false(cfg.stamina_enabled, "Infinite sprint (stamina_enabled = false) must be default")
	assert_almost_eq(cfg.max_stamina, 100.0, 0.001, "Default max_stamina must be 100.0")
	assert_almost_eq(cfg.coyote_time, 0.1, 0.001, "Default coyote_time must be 0.1 s")
	assert_almost_eq(cfg.step_height, 0.35, 0.001, "Default step_height must be 0.35 m")
	assert_almost_eq(cfg.fall_damage_min_speed, 12.0, 0.001, "Default fall_damage_min_speed must be 12.0 m/s")
	assert_almost_eq(cfg.calculate_fall_damage(-10.0), 0.0, 0.001, "No fall damage at -10 m/s")
	assert_almost_eq(cfg.calculate_fall_damage(-12.0), 0.0, 0.001, "No fall damage at threshold -12 m/s")
	assert_gt(cfg.calculate_fall_damage(-15.0), 0.0, "Fall damage must be positive below -12 m/s")


func test_sprint_only_forward_and_blocked_in_crouch_or_prone() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var arena: Node3D = _create_test_arena()
	tree.root.add_child(arena)
	var player: Player = arena.get_node("Player") as Player
	var cfg: MovementConfig = player.movement_config
	await _settle_player(tree, player)

	var back_sprint: PlayerInput = PlayerInput.new()
	back_sprint.move = Vector2(0.0, -1.0)
	back_sprint.buttons = PlayerInput.BTN_SPRINT
	await _step_ticks(tree, player, back_sprint, 30)
	assert_false(player.motor.is_sprinting, "Cannot sprint while moving backward")
	assert_almost_eq(Vector2(player.velocity.x, player.velocity.z).length(), cfg.walk_speed, 0.05)

	var strafe_sprint: PlayerInput = PlayerInput.new()
	strafe_sprint.move = Vector2(1.0, 0.0)
	strafe_sprint.buttons = PlayerInput.BTN_SPRINT
	await _step_ticks(tree, player, strafe_sprint, 30)
	assert_false(player.motor.is_sprinting, "Cannot sprint while strafing purely sideways")
	assert_almost_eq(Vector2(player.velocity.x, player.velocity.z).length(), cfg.walk_speed, 0.05)

	var crouch_sprint: PlayerInput = PlayerInput.new()
	crouch_sprint.move = Vector2(0.0, 1.0)
	crouch_sprint.buttons = PlayerInput.BTN_SPRINT | PlayerInput.BTN_CROUCH
	await _step_ticks(tree, player, crouch_sprint, 30)
	assert_false(player.motor.is_sprinting, "Cannot sprint in crouch")
	assert_almost_eq(Vector2(player.velocity.x, player.velocity.z).length(), cfg.crouch_speed, 0.05)

	var prone_sprint: PlayerInput = PlayerInput.new()
	prone_sprint.move = Vector2(0.0, 1.0)
	prone_sprint.buttons = PlayerInput.BTN_SPRINT | PlayerInput.BTN_PRONE
	await _step_ticks(tree, player, prone_sprint, 30)
	assert_false(player.motor.is_sprinting, "Cannot sprint in prone")
	assert_almost_eq(Vector2(player.velocity.x, player.velocity.z).length(), cfg.prone_speed, 0.05)

	tree.root.remove_child(arena)
	arena.free()


func test_optional_stamina_drains_and_regenerates() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var arena: Node3D = _create_test_arena()
	tree.root.add_child(arena)
	var player: Player = arena.get_node("Player") as Player
	var cfg: MovementConfig = player.movement_config
	cfg.stamina_enabled = true
	cfg.max_stamina = 20.0
	cfg.stamina_drain_rate = 40.0
	cfg.stamina_regen_rate = 40.0
	cfg.stamina_regen_delay = 0.2
	player.motor.stamina = cfg.max_stamina
	await _settle_player(tree, player)

	var sprint_inp: PlayerInput = PlayerInput.new()
	sprint_inp.move = Vector2(0.0, 1.0)
	sprint_inp.buttons = PlayerInput.BTN_SPRINT
	await _step_ticks(tree, player, sprint_inp, 15)
	assert_true(player.motor.is_sprinting, "Player must sprint while stamina > 0")
	assert_lt(player.motor.stamina, cfg.max_stamina, "Stamina must drain while sprinting")

	await _step_ticks(tree, player, sprint_inp, 30)
	assert_almost_eq(player.motor.stamina, 0.0, 0.001, "Stamina must reach 0")
	assert_false(player.motor.is_sprinting, "Sprint must stop when stamina is depleted")
	var exhausted_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	assert_almost_eq(exhausted_speed, cfg.walk_speed, 0.05, "Exhausted player must slow down to walk_speed")

	var walk_inp: PlayerInput = PlayerInput.new()
	walk_inp.move = Vector2(0.0, 1.0)
	await _step_ticks(tree, player, walk_inp, 45)
	assert_gt(player.motor.stamina, 10.0, "Stamina must regenerate after regen delay when not sprinting")

	tree.root.remove_child(arena)
	arena.free()


func test_coyote_time_allows_jump_within_0_1s_after_leaving_ledge() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var arena: Node3D = Node3D.new()
	_add_static_box(arena, "Ledge", Vector3(4.0, 1.0, 4.0), Vector3(0.0, -0.5, 0.0))
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	var player: Player = packed.instantiate() as Player
	player.is_local_player = false
	player.position = Vector3(0.0, 0.05, -1.95)
	arena.add_child(player)
	tree.root.add_child(arena)
	await _settle_player(tree, player)
	assert_true(player.is_on_floor(), "Player must start on ledge")

	player.global_position = Vector3(0.0, 0.05, -2.6)
	var fall_inp: PlayerInput = PlayerInput.new()
	await _step_ticks(tree, player, fall_inp, 3)
	assert_false(player.is_on_floor(), "Player must be airborne after leaving ledge")
	assert_gt(player.motor.coyote_timer, 0.0, "Coyote timer must still be positive at 0.05 s")

	var jump_inp: PlayerInput = PlayerInput.new()
	jump_inp.buttons = PlayerInput.BTN_JUMP
	await _step_ticks(tree, player, jump_inp, 1)
	assert_gt(player.velocity.y, 3.0, "Player must be able to jump within 0.1 s coyote time")

	await _step_ticks(tree, player, jump_inp, 1)
	assert_lt(player.velocity.y, player.movement_config.jump_velocity, "Cannot double-jump after coyote jump")

	player.global_position = Vector3(0.0, 0.05, 0.0)
	player.velocity = Vector3.ZERO
	await _settle_player(tree, player)
	player.global_position = Vector3(0.0, 0.05, -2.6)
	await _step_ticks(tree, player, fall_inp, 10)
	assert_almost_eq(player.motor.coyote_timer, 0.0, 0.001, "Coyote timer must expire after > 0.1 s")
	await _step_ticks(tree, player, jump_inp, 1)
	assert_lt(player.velocity.y, 0.0, "Jump must not trigger after coyote time expires")

	tree.root.remove_child(arena)
	arena.free()


func test_step_up_climbs_0_35m_and_blocks_higher_obstacles() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var arena: Node3D = _create_test_arena()
	_add_static_box(arena, "Step035", Vector3(3.0, 0.35, 2.0), Vector3(0.0, 0.175, -2.0))
	_add_static_box(arena, "Wall050", Vector3(3.0, 0.50, 2.0), Vector3(0.0, 0.25, -6.0))
	tree.root.add_child(arena)
	var player: Player = arena.get_node("Player") as Player
	await _settle_player(tree, player)

	var move_inp: PlayerInput = PlayerInput.new()
	move_inp.move = Vector2(0.0, 1.0)
	await _step_ticks(tree, player, move_inp, 45)
	assert_almost_eq(player.global_position.y, 0.35, 0.02, "Player must auto step-up onto 0.35 m step")
	assert_lt(player.global_position.z, -1.2, "Player must advance onto 0.35 m step")

	player.global_position = Vector3(0.0, 0.05, -4.2)
	player.velocity = Vector3.ZERO
	await _settle_player(tree, player)
	await _step_ticks(tree, player, move_inp, 45)
	assert_almost_eq(player.global_position.y, 0.0, 0.02, "Player must not auto step-up onto 0.50 m obstacle")
	assert_gt(player.global_position.z, -4.75, "Player must be stopped by 0.50 m obstacle")

	tree.root.remove_child(arena)
	arena.free()


func test_stairs_on_testbed_climbed_at_sprint_without_bouncing() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var testbed: Node3D = (load(TESTBED_SCENE_PATH) as PackedScene).instantiate() as Node3D
	var player: Player = testbed.get_node("Player") as Player
	player.is_local_player = false
	player.position = Vector3(6.0, 0.05, -4.8)
	tree.root.add_child(testbed)
	await _settle_player(tree, player)
	assert_true(player.is_on_floor(), "Player must start on floor in front of stairs")

	var sprint_inp: PlayerInput = PlayerInput.new()
	sprint_inp.move = Vector2(0.0, 1.0)
	sprint_inp.buttons = PlayerInput.BTN_SPRINT
	var max_vy: float = 0.0
	for _i: int in range(90):
		await tree.physics_frame
		player.step_simulation(sprint_inp, TICK_DELTA)
		max_vy = maxf(max_vy, player.velocity.y)
		if player.global_position.z <= -9.5:
			break

	assert_almost_eq(player.global_position.y, 2.0, 0.03, "Player must reach top of 10-step stairs (2.0 m)")
	assert_lt(player.global_position.z, -9.3, "Player must reach top step along Z")
	assert_lte(max_vy, 0.01, "Player must climb stairs without upward velocity bounces")
	assert_true(player.is_on_floor(), "Player must remain grounded on top of stairs")

	tree.root.remove_child(testbed)
	testbed.free()


func test_fall_from_2m_is_harmless_and_fall_from_8m_deals_damage() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var arena: Node3D = _create_test_arena()
	tree.root.add_child(arena)
	var player: Player = arena.get_node("Player") as Player
	var hc: MockHealthComponent = MockHealthComponent.new()
	hc.name = "HealthComponent"
	player.add_child(hc)
	player.health_component = hc
	await _settle_player(tree, player)

	player.global_position = Vector3(0.0, 2.0, 0.0)
	player.velocity = Vector3.ZERO
	var idle_inp: PlayerInput = PlayerInput.new()
	await _step_ticks(tree, player, idle_inp, 60)
	assert_true(player.is_on_floor(), "Player must have landed after 2 m fall")
	assert_almost_eq(player.last_fall_damage, 0.0, 0.001, "Fall from 2 m must deal 0 damage")
	assert_almost_eq(hc.health, 100.0, 0.001, "HealthComponent must stay at 100 HP after 2 m fall")
	assert_eq(hc.hit_count, 0, "HealthComponent must not receive damage on 2 m fall")

	player.global_position = Vector3(0.0, 8.0, 0.0)
	player.velocity = Vector3.ZERO
	await _step_ticks(tree, player, idle_inp, 90)
	assert_true(player.is_on_floor(), "Player must have landed after 8 m fall")
	assert_gt(player.last_fall_damage, 0.0, "Fall from 8 m must deal positive fall damage")
	assert_almost_eq(hc.last_damage, player.last_fall_damage, 0.001, "HealthComponent must receive exact fall damage")
	assert_lt(hc.health, 100.0, "HealthComponent health must decrease after 8 m fall")

	tree.root.remove_child(arena)
	arena.free()
