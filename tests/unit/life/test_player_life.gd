extends GutTest

var _states: Array[int] = []
var _killers: Array[int] = []


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_states.clear()
	_killers.clear()


func _player(local: bool = false) -> Player:
	var player: Player = load("res://src/player/player.tscn").instantiate() as Player
	player.is_local_player = local
	player.position = Vector3(2200, 20, 2200)
	add_child_autofree(player)
	_freeze(player)
	player.release_mouse()
	player.life.rules = player.life.rules.duplicate() as MatchRules
	player.life.state_changed.connect(func(value: PlayerLife.State) -> void: _states.append(value))
	player.life.finally_died.connect(func(killer: int) -> void: _killers.append(killer))
	return player


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_freeze(child)


func test_default_rules_and_invalid_data() -> void:
	var rules: MatchRules = load("res://src/core/default_match_rules.tres").duplicate() as MatchRules
	assert_true(rules.is_valid())
	assert_eq(rules.bleedout_time, 20.0)
	assert_eq(rules.revive_time, 3.0)
	assert_eq(rules.revive_health_fraction, 0.3)
	for property: StringName in [&"bleedout_time", &"revive_time", &"revive_distance", &"revive_health_fraction"]:
		var original: float = rules.get(property)
		for invalid: float in [0.0, -1.0, INF, NAN]:
			rules.set(property, invalid)
			assert_false(rules.is_valid())
		rules.set(property, original)
	rules.revive_health_fraction = 1.01
	assert_false(rules.is_valid())


func test_lethal_damage_enters_downed_with_live_hitboxes_and_no_final_death() -> void:
	var player: Player = _player()
	var health: HealthComponent = player.health_component as HealthComponent
	health.apply_damage(1000.0, 17)
	assert_eq(player.life.state, PlayerLife.State.DOWNED)
	assert_eq(_states, [PlayerLife.State.DOWNED])
	assert_true(health.is_dead)
	assert_true(health.is_downed)
	assert_true(health.can_receive_damage())
	assert_eq(health.current, 0.0)
	assert_eq(player.stance, PlayerStance.PRONE)
	assert_eq(player.stance_controller.current_head_height, player.movement_config.prone_head_height)
	assert_eq(player.life.bleedout_remaining, 20.0)
	assert_true(_killers.is_empty())
	assert_eq(player.hitboxes.get_node("TorsoZone").collision_layer, HitboxZone.LAYER_HITBOXES)


func test_bleedout_exact_boundary_and_transition_order_once() -> void:
	var player: Player = _player()
	player.health_component.apply_damage(100.0, 12)
	for tick: int in range(1199):
		player.life.step(1.0 / 60.0)
	assert_eq(player.life.state, PlayerLife.State.DOWNED)
	player.life.step(1.0 / 60.0)
	assert_eq(_states, [PlayerLife.State.DOWNED, PlayerLife.State.DEAD, PlayerLife.State.SPAWN_SELECT])
	assert_eq(_killers, [12])
	player.life.step(1000.0)
	player.health_component.apply_damage(50.0, 19)
	assert_eq(_killers, [12])
	assert_false((player.health_component as HealthComponent).can_receive_damage())


func test_finish_off_uses_new_killer_and_skips_remaining_timer() -> void:
	var player: Player = _player()
	player.health_component.apply_damage(100.0, 1)
	player.health_component.apply_damage(0.0, 9)
	player.health_component.apply_damage(NAN, 9)
	assert_eq(player.life.state, PlayerLife.State.DOWNED)
	player.health_component.apply_damage(1.0, 2)
	assert_eq(player.life.state, PlayerLife.State.SPAWN_SELECT)
	assert_eq(_killers, [2])
	assert_false((player.health_component as HealthComponent).is_downed)


func test_rules_disable_downed_and_custom_bleedout_is_used() -> void:
	var player: Player = _player()
	player.life.rules.downed_enabled = false
	player.health_component.apply_damage(100.0, 3)
	assert_eq(_states, [PlayerLife.State.DEAD, PlayerLife.State.SPAWN_SELECT])
	player.health_component.reset()
	player.life.rules.downed_enabled = true
	player.life.rules.bleedout_time = 0.5
	player.health_component.apply_damage(100.0)
	player.life.step(0.49)
	assert_eq(player.life.state, PlayerLife.State.DOWNED)
	player.life.step(0.01)
	assert_eq(player.life.state, PlayerLife.State.SPAWN_SELECT)


func test_revive_restores_fraction_of_max_health_and_allows_another_down() -> void:
	var player: Player = _player()
	var health: HealthComponent = player.health_component as HealthComponent
	health.max_health = 200.0
	health.reset()
	health.apply_damage(200.0)
	assert_true(player.life.revive())
	assert_eq(health.current, 60.0)
	assert_false(health.is_dead)
	assert_false(health.is_downed)
	assert_eq(player.life.state, PlayerLife.State.ALIVE)
	assert_eq(player.stance, PlayerStance.STAND)
	assert_false(player.life.revive())
	player.life.step(1000.0)
	assert_eq(player.life.state, PlayerLife.State.ALIVE)
	health.apply_damage(60.0)
	assert_eq(player.life.state, PlayerLife.State.DOWNED)
	assert_eq(player.life.bleedout_remaining, 20.0)


func test_invalid_deltas_and_normal_healing_cannot_end_downed() -> void:
	var player: Player = _player()
	player.health_component.apply_damage(100.0)
	for delta: float in [0.0, -1.0, INF, NAN]:
		player.life.step(delta)
	player.health_component.heal(100.0)
	assert_eq(player.life.bleedout_remaining, 20.0)
	assert_eq(player.health_component.current, 0.0)
	assert_false((player.health_component as HealthComponent).restore_fraction(2.0))
	assert_false((player.health_component as HealthComponent).restore_fraction(NAN))


func test_downed_input_blocks_all_actions_and_horizontal_motion() -> void:
	var player: Player = _player()
	var ammo: int = player.weapon.ammo_in_mag
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.move = Vector2.ONE
	inp.buttons = PlayerInput.BTN_FIRE | PlayerInput.BTN_AIM | PlayerInput.BTN_JUMP | PlayerInput.BTN_RELOAD
	inp.weapon_slot = 2
	inp.throw_grenade = true
	inp.melee = true
	player.health_component.apply_damage(100.0)
	player.velocity = Vector3(10, 0, 10)
	player.step_simulation(inp, 1.0 / 60.0)
	assert_eq(player.velocity.x, 0.0)
	assert_eq(player.velocity.z, 0.0)
	assert_eq(player.weapon.ammo_in_mag, ammo)
	assert_eq(player.inventory.active_slot, 1)
	assert_false(player.equipment.melee.busy)
	assert_false(player.equipment.projectiles.system.projectiles[0].active)
	assert_eq(player.ads.target, 0.0)
	assert_eq(player.stance, PlayerStance.PRONE)
	assert_eq(player.life.filter_input(inp), player.life.filter_input(inp))


func test_spawn_screen_and_button_restore_initial_position() -> void:
	var player: Player = _player(true)
	var spawn: Transform3D = player.global_transform
	assert_false(player.life.view.spawn_panel.visible)
	player.health_component.apply_damage(100.0)
	assert_true(player.life.view.status_label.visible)
	assert_true(player.life.view.status_label.text.contains("20 s"))
	player.health_component.apply_damage(1.0)
	assert_true(player.life.view.spawn_panel.visible)
	assert_false(player.is_mouse_captured())
	player.position += Vector3(10, 0, 0)
	player.life.view.spawn_button.pressed.emit()
	assert_eq(player.life.state, PlayerLife.State.ALIVE)
	assert_eq(player.global_transform, spawn)
	assert_eq(player.health_component.current, 100.0)
	assert_true(player.is_mouse_captured())
	assert_false(player.life.view.spawn_panel.visible)
	player.release_mouse()


func test_client_cannot_damage_heal_reset_revive_advance_or_spawn() -> void:
	var player: Player = _player()
	player.health_component.apply_damage(100.0)
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 9), OK)
	api.multiplayer_peer = peer
	var path: NodePath = player.get_path()
	get_tree().set_multiplayer(api, path)
	player.life.step(1000.0)
	assert_false(player.life.revive())
	player.health_component.apply_damage(1.0)
	player.health_component.heal(100.0)
	player.health_component.reset()
	player.life.select_initial_spawn()
	assert_eq(player.life.state, PlayerLife.State.DOWNED)
	assert_eq(player.life.bleedout_remaining, 20.0)
	assert_eq(player.health_component.current, 0.0)
	get_tree().set_multiplayer(null, path)
	peer.close()


func test_repeated_down_and_revive_reuse_nodes_and_keep_rules_shared() -> void:
	var player: Player = _player()
	var node_count: int = get_tree().get_node_count()
	var rules: MatchRules = player.life.rules
	for cycle: int in range(100):
		player.health_component.apply_damage(100.0)
		assert_true(player.life.revive())
		assert_eq(player.health_component.current, 30.0)
		assert_eq(get_tree().get_node_count(), node_count)
	assert_eq(player.life.rules, rules)
	assert_eq(player.life.rules.bleedout_time, 20.0)
