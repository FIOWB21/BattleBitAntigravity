extends "res://tests/unit/combat/combat_fixture.gd"


func test_server_deadline_reuses_exact_actor_and_its_unique_spawn_slot() -> void:
	var identity: int = actor.get_instance_id()
	var count: int = get_tree().get_node_count()
	var pose: Transform3D = players.respawn_pose(42)
	actor.position += Vector3(15, 0, 20)
	_kill()
	assert_eq(players.respawns.deadlines[42], 280)
	players.respawns.step(279)
	assert_eq(actor.life.state, PlayerLife.State.SPAWN_SELECT)
	Net.tick = 280
	players.respawns.step(280)
	assert_eq(actor.life.state, PlayerLife.State.ALIVE)
	assert_eq(actor.global_transform, pose)
	assert_eq(actor.get_instance_id(), identity)
	assert_eq(players.actors.size(), 1)
	assert_eq(get_tree().get_node_count(), count)
	assert_false(players.respawns.deadlines.has(42))
	players.respawns.step(10000)
	assert_eq(actor.get_instance_id(), identity)


func test_spawn_protection_expires_at_exact_120_tick_boundary() -> void:
	_kill()
	Net.tick = 280
	players.respawns.step(280)
	var health: HealthComponent = actor.health_component as HealthComponent
	assert_eq(health.protection_until_tick, 400)
	for tick: int in range(280, 400):
		Net.tick = tick
		assert_false(health.can_receive_damage())
		health.apply_damage(1000.0)
		assert_eq(health.current, 100.0)
	Net.tick = 400
	assert_true(health.can_receive_damage())
	health.apply_damage(1.0)
	assert_eq(health.current, 99.0)


func test_downed_has_no_deadline_and_finish_off_schedules_only_once() -> void:
	actor.health_component.apply_damage(100.0, 1)
	assert_true(players.respawns.deadlines.is_empty())
	actor.health_component.apply_damage(1.0, 2)
	assert_eq(players.respawns.deadlines.size(), 1)
	var deadline: int = players.respawns.deadlines[42]
	Net.tick += 10
	actor.health_component.apply_damage(1000.0, 3)
	assert_eq(players.respawns.deadlines[42], deadline)
	assert_false(actor.life.spawn_at(Transform3D.IDENTITY))
	actor.life.select_initial_spawn()
	assert_eq(actor.life.state, PlayerLife.State.SPAWN_SELECT)


func test_respawn_restores_health_loadout_grenades_stance_and_movement() -> void:
	actor.weapon.ammo_in_mag = 0
	actor.weapon.reserve_ammo = 0
	actor.inventory.phase = Inventory.Phase.HOLSTERING
	actor.equipment.projectiles.grenades = 0
	actor.velocity = Vector3(5, -20, 6)
	actor.motor.coyote_timer = 0.1
	actor.motor.is_sprinting = true
	actor.stance_controller.current_lean = 1.0
	actor.stance_controller.current_lean_offset = 0.4
	actor.stance = PlayerStance.PRONE
	_kill()
	Net.tick = 280
	players.respawns.step(280)
	assert_eq(actor.health_component.current, actor.health_component.max_health)
	assert_false(actor.health_component.is_dead)
	assert_eq(actor.inventory.active_slot, Loadout.Slot.PRIMARY)
	assert_eq(actor.inventory.phase, Inventory.Phase.READY)
	assert_eq(actor.weapon.ammo_in_mag, actor.weapon.data.mag_size)
	assert_eq(actor.weapon.reserve_ammo, actor.weapon.reserve_capacity())
	assert_eq(actor.equipment.projectiles.grenades, actor.equipment.projectiles.stock.initial_count)
	assert_eq(actor.velocity, Vector3.ZERO)
	assert_eq(actor.stance, PlayerStance.STAND)
	assert_eq(actor.stance_controller.current_lean, 0.0)
	assert_eq(actor.head.rotation, Vector3.ZERO)
	assert_eq(actor.ads.target, 0.0)
	assert_false(actor.motor.is_sprinting)


func test_disconnect_cancels_pending_respawn_and_clears_world_records() -> void:
	_kill()
	actor.free()
	assert_true(players.actors.is_empty())
	assert_true(players.respawns.deadlines.is_empty())
	assert_true(players.respawns.spawn_ticks.is_empty())
	assert_true(players.respawns._actors.is_empty())
	players.respawns.step(10000)


func test_client_cannot_advance_respawn_deadlines_or_refill_gameplay() -> void:
	_kill()
	var api: SceneMultiplayer = SceneMultiplayer.new()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 1), OK)
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, loader.get_path())
	actor.weapon.ammo_in_mag = 0
	players.respawns.step(10000)
	SpawnState.refill(actor)
	assert_eq(actor.life.state, PlayerLife.State.SPAWN_SELECT)
	assert_eq(actor.weapon.ammo_in_mag, 0)
	assert_eq(players.respawns.deadlines[42], 280)
	peer.close()
	get_tree().set_multiplayer(null, loader.get_path())


func test_rules_validate_finite_positive_respawn_and_nonnegative_protection() -> void:
	var rules: MatchRules = actor.life.rules
	for value: float in [0.0, -1.0, NAN, INF]:
		rules.respawn_delay = value
		assert_false(rules.is_valid())
	rules.respawn_delay = 3.0
	for value: float in [-1.0, NAN, INF]:
		rules.spawn_protection = value
		assert_false(rules.is_valid())
	rules.spawn_protection = 0.0
	assert_true(rules.is_valid())
