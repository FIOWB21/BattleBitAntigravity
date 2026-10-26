extends GutTest

const PLAYER_SCENE_PATH: String = "res://src/player/player.tscn"
const TESTBED_SCENE_PATH: String = "res://src/maps/testbed/testbed.tscn"
const DEFAULT_HITBOXES_PATH: String = "res://src/player/default_hitboxes.tres"
const TICK_DELTA: float = 1.0 / 60.0


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


func test_hitbox_zone_properties_layers_and_damage_mult() -> void:
	var cfg: HitboxConfig = load(DEFAULT_HITBOXES_PATH) as HitboxConfig
	assert_not_null(cfg, "default_hitboxes.tres must load")
	assert_almost_eq(cfg.multiplier_for(HitboxZone.HEAD), 2.0, 0.001, "Head mult must be 2.0")
	assert_almost_eq(cfg.multiplier_for(HitboxZone.TORSO), 1.0, 0.001, "Torso mult must be 1.0")
	assert_almost_eq(cfg.multiplier_for(HitboxZone.ARMS), 0.8, 0.001, "Arms mult must be 0.8")
	assert_almost_eq(cfg.multiplier_for(HitboxZone.LEGS), 0.75, 0.001, "Legs mult must be 0.75")

	var hc: HealthComponent = HealthComponent.new()
	add_child_autofree(hc)
	var zone_node: HitboxZone = HitboxZone.new()
	add_child_autofree(zone_node)
	zone_node.configure(HitboxZone.HEAD, cfg.multiplier_for(HitboxZone.HEAD), hc)

	assert_eq(zone_node.collision_layer, HitboxZone.LAYER_HITBOXES, "HitboxZone must be on layer hitboxes (4)")
	assert_eq(zone_node.collision_mask, 0, "HitboxZone collision_mask must be 0")
	assert_false(zone_node.monitoring, "HitboxZone monitoring must be false")
	assert_eq(zone_node.owner_health, hc, "owner_health must point to HealthComponent")

	var recorded_zone: Array[int] = []
	var recorded_amount: Array[float] = []
	hc.damaged.connect(func(amount: float, _source_id: int, hit_zone: int) -> void:
		recorded_amount.append(amount)
		recorded_zone.append(hit_zone)
	)
	var dealt: float = zone_node.apply_damage(30.0, 5)
	assert_almost_eq(dealt, 60.0, 0.001, "30 base damage on HEAD (2.0x) must deal 60")
	assert_almost_eq(hc.current, 40.0, 0.001, "HealthComponent current must drop to 40")
	assert_eq(recorded_zone.size(), 1)
	assert_eq(recorded_zone[0], HitboxZone.HEAD)


func test_hitscan_query_hits_head_torso_arms_legs_and_world_on_testbed() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var testbed: Node3D = (load(TESTBED_SCENE_PATH) as PackedScene).instantiate() as Node3D
	var player: Player = testbed.get_node("Player") as Player
	player.is_local_player = false
	player.position = Vector3(0.0, 0.05, 0.0)
	player.rotation = Vector3.ZERO
	tree.root.add_child(testbed)
	await _settle_player(tree, player)
	await tree.physics_frame

	var base_pos: Vector3 = player.global_position
	var head_from: Vector3 = base_pos + Vector3(0.0, 1.65, 3.0)
	var head_to: Vector3 = base_pos + Vector3(0.0, 1.65, -3.0)
	var head_res: HitResult = HitscanQuery.cast(head_from, head_to, [])
	assert_true(head_res.hit, "Ray at y=1.65 must hit player head")
	assert_eq(head_res.zone, HitboxZone.HEAD, "Zone at y=1.65 must be HEAD")
	assert_eq(head_res.target, player.health_component, "Hit target must be player HealthComponent")
	assert_eq(head_res.entity, player, "Hit entity must be Player")
	assert_almost_eq(head_res.damage_mult, 2.0, 0.001, "Head hit damage_mult must be 2.0")
	assert_gt(head_res.normal.z, 0.9, "Hit normal must face the incoming ray (+Z)")

	var torso_from: Vector3 = base_pos + Vector3(0.0, 1.12, 3.0)
	var torso_to: Vector3 = base_pos + Vector3(0.0, 1.12, -3.0)
	var torso_res: HitResult = HitscanQuery.cast(torso_from, torso_to, [])
	assert_true(torso_res.hit, "Ray at y=1.12, x=0 must hit player torso")
	assert_eq(torso_res.zone, HitboxZone.TORSO, "Zone at y=1.12, x=0 must be TORSO")
	assert_almost_eq(torso_res.damage_mult, 1.0, 0.001, "Torso hit damage_mult must be 1.0")

	var arm_from: Vector3 = base_pos + Vector3(0.24, 1.12, 3.0)
	var arm_to: Vector3 = base_pos + Vector3(0.24, 1.12, -3.0)
	var arm_res: HitResult = HitscanQuery.cast(arm_from, arm_to, [])
	assert_true(arm_res.hit, "Ray at y=1.12, x=0.24 must hit player arm")
	assert_eq(arm_res.zone, HitboxZone.ARMS, "Zone at y=1.12, x=0.24 must be ARMS")
	assert_almost_eq(arm_res.damage_mult, 0.8, 0.001, "Arm hit damage_mult must be 0.8")

	var legs_from: Vector3 = base_pos + Vector3(0.0, 0.35, 3.0)
	var legs_to: Vector3 = base_pos + Vector3(0.0, 0.35, -3.0)
	var legs_res: HitResult = HitscanQuery.cast(legs_from, legs_to, [])
	assert_true(legs_res.hit, "Ray at y=0.35, x=0 must hit player legs")
	assert_eq(legs_res.zone, HitboxZone.LEGS, "Zone at y=0.35, x=0 must be LEGS")
	assert_almost_eq(legs_res.damage_mult, 0.75, 0.001, "Legs hit damage_mult must be 0.75")

	var floor_res: HitResult = HitscanQuery.cast(Vector3(5.0, 2.0, 5.0), Vector3(5.0, -2.0, 5.0), [])
	assert_true(floor_res.hit, "Downward ray must hit testbed floor")
	assert_eq(floor_res.zone, HitboxZone.NONE, "World hit must have zone NONE (-1)")
	assert_almost_eq(floor_res.point.y, 0.0, 0.02, "Floor hit point Y must be ~0.0")

	tree.root.remove_child(testbed)
	testbed.free()


func test_hitboxes_adapt_to_stances_and_lean() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var testbed: Node3D = (load(TESTBED_SCENE_PATH) as PackedScene).instantiate() as Node3D
	var player: Player = testbed.get_node("Player") as Player
	player.is_local_player = false
	player.position = Vector3(0.0, 0.05, 0.0)
	player.rotation = Vector3.ZERO
	tree.root.add_child(testbed)
	await _settle_player(tree, player)
	var base_pos: Vector3 = player.global_position

	var crouch_inp: PlayerInput = PlayerInput.new()
	crouch_inp.buttons = PlayerInput.BTN_CROUCH
	await _step_ticks(tree, player, crouch_inp, 15)
	await tree.physics_frame

	var stand_head_res: HitResult = HitscanQuery.cast(
		base_pos + Vector3(0.0, 1.65, 3.0),
		base_pos + Vector3(0.0, 1.65, -3.0),
		[]
	)
	assert_false(stand_head_res.hit, "Standing head ray (y=1.65) must miss crouched player")

	var crouch_head_res: HitResult = HitscanQuery.cast(
		base_pos + Vector3(0.0, 1.05, 3.0),
		base_pos + Vector3(0.0, 1.05, -3.0),
		[]
	)
	assert_true(crouch_head_res.hit, "Ray at y=1.05 must hit crouched player")
	assert_eq(crouch_head_res.zone, HitboxZone.HEAD, "Zone at y=1.05 in CROUCH must be HEAD")

	var crouch_torso_res: HitResult = HitscanQuery.cast(
		base_pos + Vector3(0.0, 0.68, 3.0),
		base_pos + Vector3(0.0, 0.68, -3.0),
		[]
	)
	assert_true(crouch_torso_res.hit, "Ray at y=0.68 in CROUCH must hit TORSO")
	assert_eq(crouch_torso_res.zone, HitboxZone.TORSO)

	var prone_inp: PlayerInput = PlayerInput.new()
	prone_inp.buttons = PlayerInput.BTN_PRONE
	await _step_ticks(tree, player, prone_inp, 15)
	await tree.physics_frame

	var crouch_ray_on_prone: HitResult = HitscanQuery.cast(
		base_pos + Vector3(0.0, 1.05, 3.0),
		base_pos + Vector3(0.0, 1.05, -3.0),
		[]
	)
	assert_false(crouch_ray_on_prone.hit, "Crouch head ray (y=1.05) must miss prone player")

	var prone_head_res: HitResult = HitscanQuery.cast(
		base_pos + Vector3(0.0, 0.35, 3.0),
		base_pos + Vector3(0.0, 0.35, -3.0),
		[]
	)
	assert_true(prone_head_res.hit, "Ray at y=0.35 must hit prone player head")
	assert_eq(prone_head_res.zone, HitboxZone.HEAD, "Zone at y=0.35 in PRONE must be HEAD")

	player.stance = PlayerStance.STAND
	var lean_r_inp: PlayerInput = PlayerInput.new()
	lean_r_inp.buttons = PlayerInput.BTN_LEAN_R
	await _step_ticks(tree, player, lean_r_inp, 20)
	await tree.physics_frame

	var leaned_head_res: HitResult = HitscanQuery.cast(
		base_pos + Vector3(0.4, 1.65, 3.0),
		base_pos + Vector3(0.4, 1.65, -3.0),
		[]
	)
	assert_true(leaned_head_res.hit, "Ray at x=+0.4, y=1.65 must hit leaned head")
	assert_eq(leaned_head_res.zone, HitboxZone.HEAD)

	tree.root.remove_child(testbed)
	testbed.free()


func test_hitscan_exclude_and_hitboxes_do_not_impede_movement() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var testbed: Node3D = (load(TESTBED_SCENE_PATH) as PackedScene).instantiate() as Node3D
	var shooter: Player = testbed.get_node("Player") as Player
	shooter.is_local_player = false
	shooter.position = Vector3(0.0, 0.05, 0.0)
	shooter.rotation = Vector3.ZERO

	var target_player: Player = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as Player
	target_player.name = "TargetPlayer"
	target_player.is_local_player = false
	target_player.position = Vector3(0.0, 0.05, -5.0)
	testbed.add_child(target_player)

	tree.root.add_child(testbed)
	await _settle_player(tree, shooter)
	await _settle_player(tree, target_player)
	await tree.physics_frame

	for zone_node: HitboxZone in shooter.hitboxes.get_zones():
		assert_eq(zone_node.collision_layer, HitboxZone.LAYER_HITBOXES, "Must be on layer hitboxes (4)")
		assert_eq(zone_node.collision_layer & 2, 0, "HitboxZone must NOT be on layer players (2)")
		assert_eq(zone_node.collision_layer & 1, 0, "HitboxZone must NOT be on layer world (1)")

	var shot_from: Vector3 = shooter.global_position + shooter.head.position
	var shot_to: Vector3 = target_player.global_position + Vector3(0.0, 1.65, -1.0)
	var hit_res: HitResult = HitscanQuery.cast(
		shot_from,
		shot_to,
		shooter.get_hitscan_exclude_rids()
	)
	assert_true(hit_res.hit, "Shot from inside shooter head with exclude must hit target")
	assert_eq(hit_res.entity, target_player, "Shot must hit TargetPlayer, not shooter")
	assert_eq(hit_res.zone, HitboxZone.HEAD, "Shot at target head height must register HEAD")

	var walk_inp: PlayerInput = PlayerInput.new()
	walk_inp.move = Vector2(0.0, 1.0)
	var start_z: float = shooter.global_position.z
	await _step_ticks(tree, shooter, walk_inp, 60)
	assert_lt(shooter.global_position.z, start_z - 3.5, "Hitboxes must not block or slow player movement")

	tree.root.remove_child(testbed)
	testbed.free()
