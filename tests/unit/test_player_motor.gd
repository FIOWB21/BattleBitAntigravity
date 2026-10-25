extends GutTest

const PLAYER_SCENE_PATH: String = "res://src/player/player.tscn"
const TESTBED_SCENE_PATH: String = "res://src/maps/testbed/testbed.tscn"
const DEFAULT_MOVEMENT_PATH: String = "res://src/player/default_movement.tres"
const TICK_DELTA: float = 1.0 / 60.0


func _create_test_arena() -> Node3D:
	var arena: Node3D = Node3D.new()
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	col.shape = box
	floor_body.add_child(col)
	arena.add_child(floor_body)

	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	var player: Player = packed.instantiate() as Player
	player.name = "Player"
	player.is_local_player = false
	player.position = Vector3(0.0, 0.05, 0.0)
	arena.add_child(player)
	return arena


func _settle_player_on_floor(tree: SceneTree, player: Player, motor: PlayerMotor, cfg: MovementConfig) -> void:
	var idle_inp: PlayerInput = PlayerInput.new()
	for _i: int in range(15):
		await tree.physics_frame
		motor.simulate(player, idle_inp, cfg, MovementConfig.STANCE_STAND, TICK_DELTA)
		if player.is_on_floor() and absf(player.velocity.y) < 0.001:
			break


func test_player_input_bitmask_and_fields() -> void:
	var inp: PlayerInput = PlayerInput.new()
	assert_eq(inp.tick, 0, "Default tick must be 0")
	assert_eq(inp.move, Vector2.ZERO, "Default move must be ZERO")
	assert_false(inp.pressed(PlayerInput.BTN_JUMP), "Jump must not be pressed initially")

	inp.buttons = PlayerInput.BTN_JUMP | PlayerInput.BTN_SPRINT | PlayerInput.BTN_LEAN_R
	assert_true(inp.pressed(PlayerInput.BTN_JUMP), "BTN_JUMP must be pressed")
	assert_true(inp.pressed(PlayerInput.BTN_SPRINT), "BTN_SPRINT must be pressed")
	assert_true(inp.pressed(PlayerInput.BTN_LEAN_R), "BTN_LEAN_R must be pressed")
	assert_false(inp.pressed(PlayerInput.BTN_CROUCH), "BTN_CROUCH must not be pressed")
	assert_false(inp.pressed(PlayerInput.BTN_FIRE), "BTN_FIRE must not be pressed")


func test_movement_config_and_default_resource() -> void:
	var cfg: MovementConfig = load(DEFAULT_MOVEMENT_PATH) as MovementConfig
	assert_not_null(cfg, "default_movement.tres must load as MovementConfig")
	assert_almost_eq(cfg.walk_speed, 4.0, 0.001, "Walk speed must be 4.0 m/s")
	assert_almost_eq(cfg.sprint_speed, 6.5, 0.001, "Sprint speed must be 6.5 m/s")
	assert_almost_eq(cfg.crouch_speed, 2.0, 0.001, "Crouch speed must be 2.0 m/s")
	assert_almost_eq(cfg.prone_speed, 0.8, 0.001, "Prone speed must be 0.8 m/s")
	assert_almost_eq(cfg.speed_for(MovementConfig.STANCE_STAND, false), 4.0, 0.001, "Stand walk speed")
	assert_almost_eq(cfg.speed_for(MovementConfig.STANCE_STAND, true), 6.5, 0.001, "Stand sprint speed")
	assert_almost_eq(cfg.speed_for(MovementConfig.STANCE_CROUCH, true), 2.0, 0.001, "Crouch speed")
	assert_almost_eq(cfg.speed_for(MovementConfig.STANCE_PRONE, true), 0.8, 0.001, "Prone speed")
	var expected_v0: float = sqrt(2.0 * cfg.gravity * cfg.jump_height)
	assert_almost_eq(cfg.jump_velocity, expected_v0, 0.001, "jump_velocity must match kinematics")


func test_local_input_reader_reads_actions() -> void:
	var reader: LocalInputReader = LocalInputReader.new()
	reader.yaw = 0.5
	reader.pitch = -0.25
	Input.action_press(InputActions.MOVE_FORWARD)
	Input.action_press(InputActions.SPRINT)
	Input.action_press(InputActions.JUMP)
	var inp: PlayerInput = reader.read_input()
	Input.action_release(InputActions.MOVE_FORWARD)
	Input.action_release(InputActions.SPRINT)
	Input.action_release(InputActions.JUMP)

	assert_eq(inp.tick, 1, "Tick must increment to 1")
	assert_almost_eq(inp.move.x, 0.0, 0.001, "Move X must be 0")
	assert_almost_eq(inp.move.y, 1.0, 0.001, "Move Y must be 1 when MOVE_FORWARD is pressed")
	assert_almost_eq(inp.yaw, 0.5, 0.001, "Yaw must propagate from reader")
	assert_almost_eq(inp.pitch, -0.25, 0.001, "Pitch must propagate from reader")
	assert_true(inp.pressed(PlayerInput.BTN_SPRINT), "BTN_SPRINT must be captured")
	assert_true(inp.pressed(PlayerInput.BTN_JUMP), "BTN_JUMP must be captured")


func test_player_scene_structure_and_layers() -> void:
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	assert_not_null(packed, "player.tscn must load as PackedScene")
	var player: Player = packed.instantiate() as Player
	assert_not_null(player, "player.tscn root must be Player (CharacterBody3D)")
	assert_eq(player.collision_layer, 2, "Player must be on layer players (2)")
	assert_eq(player.collision_mask, 1, "Player must have collision mask world (1)")

	var col: CollisionShape3D = player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	assert_not_null(col, "Player must have CollisionShape3D")
	var capsule: CapsuleShape3D = col.shape as CapsuleShape3D
	assert_not_null(capsule, "Player shape must be CapsuleShape3D")
	assert_almost_eq(capsule.height, 1.8, 0.001, "Capsule height must be 1.8 m")
	assert_almost_eq(capsule.radius, 0.35, 0.001, "Capsule radius must be 0.35 m")
	assert_not_null(player.get_node_or_null("Head") as Node3D, "Player must have Head Node3D")
	assert_not_null(player.get_node_or_null("Head/Camera3D") as Camera3D, "Head must have Camera3D")
	player.free()


func test_motor_zero_input_decelerates_to_zero() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var arena: Node3D = _create_test_arena()
	tree.root.add_child(arena)
	var player: Player = arena.get_node("Player") as Player
	var motor: PlayerMotor = PlayerMotor.new()
	var cfg: MovementConfig = player.movement_config
	await _settle_player_on_floor(tree, player, motor, cfg)
	assert_true(player.is_on_floor(), "Player must be on floor before deceleration test")

	player.velocity = Vector3(3.5, 0.0, -3.5)
	var empty_inp: PlayerInput = PlayerInput.new()
	for _i: int in range(60):
		await tree.physics_frame
		motor.simulate(player, empty_inp, cfg, MovementConfig.STANCE_STAND, TICK_DELTA)

	var horiz_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	assert_almost_eq(horiz_speed, 0.0, 0.001, "Velocity must decay to 0 on empty input")
	tree.root.remove_child(arena)
	arena.free()


func test_motor_forward_move_reaches_target_speed_in_one_second() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var arena: Node3D = _create_test_arena()
	tree.root.add_child(arena)
	var player: Player = arena.get_node("Player") as Player
	var motor: PlayerMotor = PlayerMotor.new()
	var cfg: MovementConfig = player.movement_config
	await _settle_player_on_floor(tree, player, motor, cfg)

	var walk_inp: PlayerInput = PlayerInput.new()
	walk_inp.move = Vector2(0.0, 1.0)
	for _i: int in range(60):
		await tree.physics_frame
		motor.simulate(player, walk_inp, cfg, MovementConfig.STANCE_STAND, TICK_DELTA)
	var walk_vel: float = Vector2(player.velocity.x, player.velocity.z).length()
	assert_almost_eq(walk_vel, cfg.walk_speed, 0.05, "Speed after 1s of move=(0,1) must equal walk_speed")
	assert_almost_eq(player.velocity.z, -cfg.walk_speed, 0.05, "Forward movement must be along -Z")

	var sprint_inp: PlayerInput = PlayerInput.new()
	sprint_inp.move = Vector2(0.0, 1.0)
	sprint_inp.buttons = PlayerInput.BTN_SPRINT
	for _i: int in range(60):
		await tree.physics_frame
		motor.simulate(player, sprint_inp, cfg, MovementConfig.STANCE_STAND, TICK_DELTA)
	var sprint_vel: float = Vector2(player.velocity.x, player.velocity.z).length()
	assert_almost_eq(sprint_vel, cfg.sprint_speed, 0.05, "Sprint speed after 1s must equal sprint_speed")
	tree.root.remove_child(arena)
	arena.free()


func test_motor_jump_reaches_expected_height_within_5_percent() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var arena: Node3D = _create_test_arena()
	tree.root.add_child(arena)
	var player: Player = arena.get_node("Player") as Player
	var motor: PlayerMotor = PlayerMotor.new()
	var cfg: MovementConfig = player.movement_config
	await _settle_player_on_floor(tree, player, motor, cfg)
	assert_true(player.is_on_floor(), "Player must start on floor before jump")

	var start_y: float = player.global_position.y
	var max_y: float = start_y
	var jump_inp: PlayerInput = PlayerInput.new()
	jump_inp.buttons = PlayerInput.BTN_JUMP
	await tree.physics_frame
	motor.simulate(player, jump_inp, cfg, MovementConfig.STANCE_STAND, TICK_DELTA)
	max_y = maxf(max_y, player.global_position.y)

	var air_inp: PlayerInput = PlayerInput.new()
	for _i: int in range(90):
		await tree.physics_frame
		motor.simulate(player, air_inp, cfg, MovementConfig.STANCE_STAND, TICK_DELTA)
		max_y = maxf(max_y, player.global_position.y)

	var actual_height: float = max_y - start_y
	var tolerance: float = cfg.jump_height * 0.05
	assert_almost_eq(
		actual_height,
		cfg.jump_height,
		tolerance,
		"Jump apex height must be within +-5% of expected jump_height"
	)
	tree.root.remove_child(arena)
	arena.free()


func test_player_walks_and_climbs_45deg_ramp_on_testbed() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var testbed: Node3D = (load(TESTBED_SCENE_PATH) as PackedScene).instantiate() as Node3D
	var player: Player = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as Player
	player.is_local_player = false
	player.position = Vector3(0.0, 0.05, -9.2)
	testbed.add_child(player)
	tree.root.add_child(testbed)

	await _settle_player_on_floor(tree, player, player.motor, player.movement_config)
	var start_y: float = player.global_position.y
	var start_z: float = player.global_position.z
	var forward_inp: PlayerInput = PlayerInput.new()
	forward_inp.move = Vector2(0.0, 1.0)
	for _i: int in range(60):
		await tree.physics_frame
		player.step_simulation(forward_inp, TICK_DELTA)

	assert_true(player.global_position.z < start_z - 1.5, "Player must advance along 45 deg ramp")
	assert_true(player.global_position.y > start_y + 0.8, "Player must climb 45 deg ramp height")
	assert_true(player.is_on_floor(), "Player must stay on floor on 45 deg ramp")
	tree.root.remove_child(testbed)
	testbed.free()
