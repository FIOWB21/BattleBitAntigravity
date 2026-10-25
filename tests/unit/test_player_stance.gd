extends GutTest

const PLAYER_SCENE_PATH: String = "res://src/player/player.tscn"
const TESTBED_SCENE_PATH: String = "res://src/maps/testbed/testbed.tscn"
const DEFAULT_MOVEMENT_PATH: String = "res://src/player/default_movement.tres"
const TICK_DELTA: float = 1.0 / 60.0


func _create_test_arena() -> Node3D:
	var arena: Node3D = Node3D.new()
	_add_static_box(arena, "Floor", Vector3(100.0, 1.0, 100.0), Vector3(0.0, -0.5, 0.0))
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	var player: Player = packed.instantiate() as Player
	player.name = "Player"
	player.is_local_player = false
	player.position = Vector3(0.0, 0.05, 0.0)
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


func test_stance_enum_and_config_values() -> void:
	assert_eq(PlayerStance.STAND, 0, "PlayerStance.STAND must be 0")
	assert_eq(PlayerStance.CROUCH, 1, "PlayerStance.CROUCH must be 1")
	assert_eq(PlayerStance.PRONE, 2, "PlayerStance.PRONE must be 2")

	var cfg: MovementConfig = load(DEFAULT_MOVEMENT_PATH) as MovementConfig
	assert_not_null(cfg, "default_movement.tres must load")
	assert_almost_eq(cfg.capsule_height_for(PlayerStance.STAND), 1.8, 0.001, "Stand capsule height 1.8 m")
	assert_almost_eq(cfg.capsule_height_for(PlayerStance.CROUCH), 1.2, 0.001, "Crouch capsule height 1.2 m")
	assert_almost_eq(cfg.capsule_height_for(PlayerStance.PRONE), 0.5, 0.001, "Prone capsule height 0.5 m")
	assert_almost_eq(cfg.head_height_for(PlayerStance.STAND), 1.65, 0.001, "Stand camera height 1.65 m")
	assert_almost_eq(cfg.head_height_for(PlayerStance.CROUCH), 1.05, 0.001, "Crouch camera height 1.05 m")
	assert_almost_eq(cfg.head_height_for(PlayerStance.PRONE), 0.35, 0.001, "Prone camera height 0.35 m")
	assert_almost_eq(cfg.prone_to_stand_time, 0.6, 0.001, "Prone to stand time 0.6 s")
	assert_almost_eq(cfg.lean_angle_deg, 15.0, 0.001, "Lean angle 15 deg")
	assert_almost_eq(cfg.lean_offset, 0.4, 0.001, "Lean offset 0.4 m")


func test_stance_transitions_keep_feet_on_floor_without_sinking() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var arena: Node3D = _create_test_arena()
	tree.root.add_child(arena)
	var player: Player = arena.get_node("Player") as Player
	await _settle_player(tree, player)
	var feet_y: float = player.global_position.y
	var cap: CapsuleShape3D = player.collision_shape.shape as CapsuleShape3D

	var crouch_inp: PlayerInput = PlayerInput.new()
	crouch_inp.buttons = PlayerInput.BTN_CROUCH
	await _step_ticks(tree, player, crouch_inp, 1)
	assert_lt(cap.height, 1.8, "Capsule height must start decreasing smoothly")
	assert_gt(cap.height, 1.2, "Capsule height must not snap instantaneously on tick 1")

	await _step_ticks(tree, player, crouch_inp, 15)
	assert_eq(player.stance, PlayerStance.CROUCH, "Stance must be CROUCH")
	assert_almost_eq(cap.height, 1.2, 0.001, "Crouch capsule height must be 1.2 m")
	assert_almost_eq(player.collision_shape.position.y, 0.6, 0.001, "Crouch shape center Y must be 0.6 m")
	assert_almost_eq(player.head.position.y, 1.05, 0.001, "Crouch head height must be 1.05 m")
	assert_almost_eq(player.global_position.y, feet_y, 0.005, "Feet must remain on floor in CROUCH")

	var prone_inp: PlayerInput = PlayerInput.new()
	prone_inp.buttons = PlayerInput.BTN_PRONE
	await _step_ticks(tree, player, prone_inp, 15)
	assert_eq(player.stance, PlayerStance.PRONE, "Stance must be PRONE")
	assert_almost_eq(cap.height, 0.5, 0.001, "Prone capsule height must be 0.5 m")
	assert_almost_eq(player.collision_shape.position.y, 0.25, 0.001, "Prone shape center Y must be 0.25 m")
	assert_almost_eq(player.head.position.y, 0.35, 0.001, "Prone head height must be 0.35 m")
	assert_almost_eq(player.global_position.y, feet_y, 0.005, "Feet must stay on floor in PRONE")

	tree.root.remove_child(arena)
	arena.free()


func test_prone_cannot_jump_and_transitions_to_stand_via_crouch_in_0_6s() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var arena: Node3D = _create_test_arena()
	tree.root.add_child(arena)
	var player: Player = arena.get_node("Player") as Player
	await _settle_player(tree, player)
	player.stance = PlayerStance.PRONE
	var cap: CapsuleShape3D = player.collision_shape.shape as CapsuleShape3D

	var prone_jump_inp: PlayerInput = PlayerInput.new()
	prone_jump_inp.buttons = PlayerInput.BTN_PRONE | PlayerInput.BTN_JUMP
	await _step_ticks(tree, player, prone_jump_inp, 1)
	assert_almost_eq(player.velocity.y, 0.0, 0.001, "Player must not be able to jump while prone")
	assert_eq(player.stance, PlayerStance.PRONE, "Player must stay PRONE")

	var stand_inp: PlayerInput = PlayerInput.new()
	await _step_ticks(tree, player, stand_inp, 17)
	assert_eq(player.stance, PlayerStance.PRONE, "Before 0.3s, stance is still rising from PRONE")
	await _step_ticks(tree, player, stand_inp, 1)
	assert_eq(player.stance, PlayerStance.CROUCH, "At 0.3s (18 ticks), transition must pass through CROUCH")
	assert_almost_eq(cap.height, 1.2, 0.001, "At 0.3s, capsule height must be 1.2 m")
	assert_almost_eq(player.head.position.y, 1.05, 0.001, "At 0.3s, head height must be 1.05 m")

	await _step_ticks(tree, player, stand_inp, 17)
	assert_eq(player.stance, PlayerStance.CROUCH, "Just before 0.6s (tick 35), stance is still CROUCH")
	await _step_ticks(tree, player, stand_inp, 1)
	assert_eq(player.stance, PlayerStance.STAND, "At 0.6s (36 ticks), transition to STAND must complete")
	assert_almost_eq(cap.height, 1.8, 0.001, "At 0.6s, capsule height must be 1.8 m")
	assert_almost_eq(player.head.position.y, 1.65, 0.001, "At 0.6s, head height must be 1.65 m")

	tree.root.remove_child(arena)
	arena.free()


func test_low_ceiling_blocks_standing_up() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var arena: Node3D = _create_test_arena()
	var ceiling: StaticBody3D = _add_static_box(arena, "LowCeiling", Vector3(4.0, 0.4, 4.0), Vector3(0.0, 1.6, 0.0))
	tree.root.add_child(arena)
	var player: Player = arena.get_node("Player") as Player
	player.stance = PlayerStance.PRONE
	await _settle_player(tree, player)
	var cap: CapsuleShape3D = player.collision_shape.shape as CapsuleShape3D

	var stand_inp: PlayerInput = PlayerInput.new()
	await _step_ticks(tree, player, stand_inp, 45)
	assert_eq(player.stance, PlayerStance.CROUCH, "Under 1.4m ceiling, player must stop at CROUCH")
	assert_almost_eq(cap.height, 1.2, 0.001, "Capsule height must stop at 1.2 m under 1.4 m ceiling")

	player.stance = PlayerStance.PRONE
	ceiling.position = Vector3(0.0, 1.2, 0.0)
	await _step_ticks(tree, player, stand_inp, 45)
	assert_eq(player.stance, PlayerStance.PRONE, "Under 1.0m ceiling, player must stay in PRONE")
	assert_almost_eq(cap.height, 0.5, 0.001, "Capsule height must remain 0.5 m under 1.0 m ceiling")

	tree.root.remove_child(arena)
	arena.free()


func test_tunnel_1m_on_testbed_allows_crawling_and_blocks_standing() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var testbed: Node3D = (load(TESTBED_SCENE_PATH) as PackedScene).instantiate() as Node3D
	var player: Player = testbed.get_node("Player") as Player
	player.is_local_player = false
	player.position = Vector3(18.0, 0.05, -5.6)
	tree.root.add_child(testbed)
	await _settle_player(tree, player)
	var floor_y: float = player.global_position.y

	var crawl_inp: PlayerInput = PlayerInput.new()
	crawl_inp.buttons = PlayerInput.BTN_PRONE
	crawl_inp.move = Vector2(0.0, 1.0)
	await _step_ticks(tree, player, crawl_inp, 180)
	assert_eq(player.stance, PlayerStance.PRONE, "Player must be in PRONE while crawling")
	assert_lt(player.global_position.z, -7.2, "Player must crawl inside the 1.0m tunnel")
	assert_almost_eq(player.global_position.y, floor_y, 0.01, "Player must not sink into floor in tunnel")

	var stand_inp: PlayerInput = PlayerInput.new()
	await _step_ticks(tree, player, stand_inp, 45)
	var cap: CapsuleShape3D = player.collision_shape.shape as CapsuleShape3D
	assert_eq(player.stance, PlayerStance.PRONE, "Player must not be able to stand up inside 1.0m tunnel")
	assert_almost_eq(cap.height, 0.5, 0.001, "Capsule height must remain 0.5m inside 1.0m tunnel")

	var crouch_inp: PlayerInput = PlayerInput.new()
	crouch_inp.buttons = PlayerInput.BTN_CROUCH
	await _step_ticks(tree, player, crouch_inp, 30)
	assert_eq(player.stance, PlayerStance.PRONE, "Player must not be able to crouch inside 1.0m tunnel")
	assert_almost_eq(player.global_position.y, floor_y, 0.01, "Player feet must remain on floor inside tunnel")

	tree.root.remove_child(testbed)
	testbed.free()


func test_lean_left_right_angles_offsets_and_wall_check() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var arena: Node3D = _create_test_arena()
	tree.root.add_child(arena)
	var player: Player = arena.get_node("Player") as Player
	await _settle_player(tree, player)

	var lean_l_inp: PlayerInput = PlayerInput.new()
	lean_l_inp.buttons = PlayerInput.BTN_LEAN_L
	await _step_ticks(tree, player, lean_l_inp, 20)
	assert_almost_eq(player.lean, -1.0, 0.001, "Lean state must reach -1.0 on BTN_LEAN_L")
	assert_almost_eq(player.head.position.x, -0.4, 0.001, "Head X offset must be -0.4 m when leaning left")
	assert_almost_eq(player.head.rotation.z, deg_to_rad(15.0), 0.001, "Head roll must be +15 deg when leaning left")

	var lean_r_inp: PlayerInput = PlayerInput.new()
	lean_r_inp.buttons = PlayerInput.BTN_LEAN_R
	await _step_ticks(tree, player, lean_r_inp, 30)
	assert_almost_eq(player.lean, 1.0, 0.001, "Lean state must reach +1.0 on BTN_LEAN_R")
	assert_almost_eq(player.head.position.x, 0.4, 0.001, "Head X offset must be +0.4 m when leaning right")
	assert_almost_eq(player.head.rotation.z, -deg_to_rad(15.0), 0.001, "Head roll must be -15 deg when leaning right")

	await _step_ticks(tree, player, PlayerInput.new(), 20)
	assert_almost_eq(player.head.position.x, 0.0, 0.001, "Head X offset must return to 0")
	assert_almost_eq(player.head.rotation.z, 0.0, 0.001, "Head roll must return to 0")

	_add_static_box(arena, "RightWall", Vector3(0.2, 3.0, 4.0), Vector3(0.35, 1.5, 0.0))
	await _step_ticks(tree, player, lean_r_inp, 25)
	assert_lt(player.head.position.x, 0.15, "Wall check must clamp right lean offset near wall")
	await _step_ticks(tree, player, lean_l_inp, 30)
	assert_almost_eq(player.head.position.x, -0.4, 0.001, "Leaning away from wall must reach full -0.4 m")

	tree.root.remove_child(arena)
	arena.free()
