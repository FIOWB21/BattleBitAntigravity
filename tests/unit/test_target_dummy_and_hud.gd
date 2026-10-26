extends GutTest

const TARGET_DUMMY_SCENE_PATH: String = "res://src/maps/testbed/target_dummy.tscn"
const HUD_SCENE_PATH: String = "res://src/ui/hud/hud.tscn"
const TESTBED_SCENE_PATH: String = "res://src/maps/testbed/testbed.tscn"
const TICK_DELTA: float = 1.0 / 60.0


func before_each() -> void:
	Game.reset_debug()


func after_each() -> void:
	Game.reset_debug()


func test_target_dummy_standing_hitscan_death_and_respawn_after_3s() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var packed: PackedScene = load(TARGET_DUMMY_SCENE_PATH) as PackedScene
	assert_not_null(packed, "target_dummy.tscn must load as PackedScene")
	var dummy: TargetDummy = packed.instantiate() as TargetDummy
	assert_not_null(dummy, "target_dummy.tscn root must be TargetDummy")
	dummy.position = Vector3(0.0, 0.0, 0.0)
	tree.root.add_child(dummy)
	await tree.physics_frame
	await tree.physics_frame

	assert_not_null(dummy.health_component, "TargetDummy must have HealthComponent")
	assert_almost_eq(dummy.health_component.current, 100.0, 0.001, "Initial health must be 100")
	assert_false(dummy.is_dead, "TargetDummy must start alive")
	assert_true(dummy.visuals.visible, "Visuals must be visible when alive")

	var head_from: Vector3 = Vector3(0.0, 1.65, 2.5)
	var head_to: Vector3 = Vector3(0.0, 1.65, -2.5)
	var hit_res: HitResult = HitscanQuery.cast(head_from, head_to, [])
	assert_true(hit_res.hit, "Ray at y=1.65 must hit standing TargetDummy head")
	assert_eq(hit_res.zone, HitboxZone.HEAD, "Hit zone must be HEAD")
	assert_almost_eq(hit_res.damage_mult, 2.0, 0.001, "Head damage_mult must be 2.0")
	assert_eq(hit_res.entity, dummy, "Hit entity must be TargetDummy")

	var died_count: Array[int] = [0]
	var respawned_count: Array[int] = [0]
	dummy.died.connect(func(_killer_id: int) -> void: died_count[0] += 1)
	dummy.respawned.connect(func() -> void: respawned_count[0] += 1)

	var dealt: float = hit_res.hitbox.apply_damage(50.0, 1)
	assert_almost_eq(dealt, 100.0, 0.001, "50 base damage to head deals 100")
	assert_true(dummy.is_dead, "TargetDummy must be dead at 0 HP")
	assert_eq(died_count[0], 1, "died signal must emit once")
	assert_false(dummy.visuals.visible, "Visuals must hide when dead")
	await _check_respawn_cycle(tree, dummy, respawned_count, head_from, head_to)

	tree.root.remove_child(dummy)
	dummy.free()


func _check_respawn_cycle(
	tree: SceneTree, dummy: TargetDummy, respawned_count: Array[int], head_from: Vector3, head_to: Vector3
) -> void:
	await tree.physics_frame
	var dead_ray: HitResult = HitscanQuery.cast(head_from, head_to, [])
	assert_false(dead_ray.hit, "Dead TargetDummy hitboxes must be disabled")

	dummy.step(2.9)
	assert_true(dummy.is_dead, "TargetDummy must still be dead at 2.9s (< 3.0s)")
	assert_eq(respawned_count[0], 0, "Must not respawn before 3.0s")

	dummy.step(0.15)
	assert_false(dummy.is_dead, "TargetDummy must respawn after 3.0s")
	assert_eq(respawned_count[0], 1, "respawned signal must emit after 3.0s")
	assert_almost_eq(dummy.health_component.current, 100.0, 0.001, "Health must reset to 100 on respawn")
	assert_true(dummy.visuals.visible, "Visuals must become visible on respawn")

	await tree.physics_frame
	var revived_ray: HitResult = HitscanQuery.cast(head_from, head_to, [])
	assert_true(revived_ray.hit, "Respawned TargetDummy must be hittable again")


func test_target_dummy_moving_along_waypoints() -> void:
	var packed: PackedScene = load(TARGET_DUMMY_SCENE_PATH) as PackedScene
	var dummy: TargetDummy = packed.instantiate() as TargetDummy
	dummy.position = Vector3(0.0, 0.0, 0.0)
	dummy.set_patrol_path(
		PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0)]),
		3.0
	)
	add_child_autofree(dummy)

	for _i: int in range(60):
		dummy.step(TICK_DELTA)
	assert_almost_eq(dummy.position.x, 3.0, 0.1, "After 1s at 3 m/s dummy must be at x=3.0")

	for _i: int in range(60):
		dummy.step(TICK_DELTA)
	assert_almost_eq(dummy.position.x, 6.0, 0.1, "After 2s at 3 m/s dummy must reach waypoint x=6.0")

	for _i: int in range(60):
		dummy.step(TICK_DELTA)
	assert_almost_eq(dummy.position.x, 3.0, 0.1, "After 3s dummy must move back toward x=0.0 (at x=3.0)")

	var pos_at_death: Vector3 = dummy.position
	dummy.apply_damage(100.0)
	assert_true(dummy.is_dead, "Dummy dies after 100 damage")
	dummy.step(1.0)
	assert_almost_eq(dummy.position.x, pos_at_death.x, 0.001, "Dead dummy must not move")


func test_testbed_has_5_target_dummies_standing_and_moving() -> void:
	var testbed: Node3D = (load(TESTBED_SCENE_PATH) as PackedScene).instantiate() as Node3D
	assert_not_null(testbed, "testbed.tscn must instantiate")
	var dummies: Array[TargetDummy] = _collect_target_dummies(testbed)
	assert_eq(dummies.size(), 5, "Testbed must contain 5 TargetDummy instances")

	var standing_count: int = 0
	var moving_count: int = 0
	for d: TargetDummy in dummies:
		if d.move_enabled and d.waypoints.size() >= 2:
			moving_count += 1
		else:
			standing_count += 1
	assert_true(standing_count >= 1, "Testbed must have standing target dummies")
	assert_true(moving_count >= 1, "Testbed must have moving target dummies")
	testbed.free()


func test_hud_script_has_no_polling_process() -> void:
	var hud_script: GDScript = load("res://src/ui/hud/hud.gd") as GDScript
	var has_process: bool = false
	for method_info: Dictionary in hud_script.get_script_method_list():
		var m_name: String = String(method_info.get("name", ""))
		if m_name == "_process" or m_name == "_physics_process":
			has_process = true
	assert_false(has_process, "HUD must subscribe to signals and NOT poll in _process/_physics_process")


func test_hud_elements_and_signal_subscription() -> void:
	var packed: PackedScene = load(HUD_SCENE_PATH) as PackedScene
	assert_not_null(packed, "hud.tscn must load as PackedScene")
	var hud: HUD = packed.instantiate() as HUD
	assert_not_null(hud, "hud.tscn root must be HUD")
	add_child_autofree(hud)

	assert_not_null(hud.health_bar, "HUD must have HealthBar")
	assert_not_null(hud.health_label, "HUD must have HealthLabel")
	assert_not_null(hud.stance_label, "HUD must have StanceLabel")
	assert_not_null(hud.ammo_label, "HUD must have AmmoLabel")
	assert_not_null(hud.crosshair_dot, "HUD must have CrosshairDot")

	assert_almost_eq(hud.health_bar.value, 100.0, 0.001, "Initial HUD health bar must be 100")
	assert_eq(hud.stance_label.text, "STAND", "Initial HUD stance must be STAND")
	assert_eq(hud.ammo_label.text, "0 / 0", "Unbound HUD must not invent ammunition")

	var hc: HealthComponent = HealthComponent.new()
	add_child_autofree(hc)
	var sc: StanceController = StanceController.new()
	add_child_autofree(sc)
	hud.bind_health_component(hc)
	hud.bind_stance_controller(sc)

	hc.apply_damage(35.0)
	assert_almost_eq(hud.health_bar.value, 65.0, 0.001, "HUD health bar must update immediately via signal")
	assert_eq(hud.health_label.text, "65 / 100", "HUD health label must show 65 / 100")

	sc.set_stance_immediate(PlayerStance.CROUCH)
	assert_eq(hud.stance_label.text, "CROUCH", "HUD stance label must update to CROUCH via signal")
	sc.set_stance_immediate(PlayerStance.PRONE)
	assert_eq(hud.stance_label.text, "PRONE", "HUD stance label must update to PRONE via signal")

	hud.set_ammo(12, 90)
	assert_eq(hud.ammo_label.text, "12 / 90", "HUD ammo label must update on set_ammo()")


func test_console_damage_command_updates_player_health_and_hud_on_testbed() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var testbed: Node3D = (load(TESTBED_SCENE_PATH) as PackedScene).instantiate() as Node3D
	tree.root.add_child(testbed)

	var player: Player = testbed.get_node_or_null("Player") as Player
	var hud: HUD = testbed.get_node_or_null("HUD") as HUD
	var overlay: DebugOverlay = testbed.get_node_or_null("DebugOverlay") as DebugOverlay
	assert_not_null(player, "Testbed must have Player")
	assert_not_null(hud, "Testbed must have HUD")
	assert_not_null(overlay, "Testbed must have DebugOverlay")

	var out: String = overlay.execute_command("damage 25")
	assert_has(out, "damage: 25.0", "damage command must confirm damage")
	var hc: HealthComponent = player.health_component as HealthComponent
	assert_almost_eq(hc.current, 75.0, 0.001, "Player HealthComponent must drop to 75 after 'damage 25'")
	assert_almost_eq(hud.health_bar.value, 75.0, 0.001, "HUD HealthBar must drop to 75 after 'damage 25'")
	assert_eq(hud.health_label.text, "75 / 100", "HUD HealthLabel must show 75 / 100")

	var bad_out: String = overlay.execute_command("damage -10")
	assert_has(bad_out, "Error:", "Negative damage must return error")
	assert_almost_eq(hc.current, 75.0, 0.001, "Health unchanged after invalid damage command")

	tree.root.remove_child(testbed)
	testbed.free()


func _collect_target_dummies(node: Node) -> Array[TargetDummy]:
	var out: Array[TargetDummy] = []
	for child: Node in node.get_children():
		if child is TargetDummy:
			out.append(child as TargetDummy)
		out.append_array(_collect_target_dummies(child))
	return out
