extends "res://tests/unit/combat/combat_fixture.gd"

var deaths: Array[Dictionary] = []
var hits: Array[bool] = []
var spawns: Array[int] = []


func before_each() -> void:
	super.before_each()
	deaths.clear()
	hits.clear()
	spawns.clear()
	Events.player_died.connect(_death)
	Events.hit_confirmed.connect(_hit)
	Events.player_spawned.connect(_spawn)
	players.ready_peers[1] = true


func after_each() -> void:
	Events.player_died.disconnect(_death)
	Events.hit_confirmed.disconnect(_hit)
	Events.player_spawned.disconnect(_spawn)
	super.after_each()


func _death(victim: int, killer: int, weapon: StringName, headshot: bool) -> void:
	deaths.append({"victim": victim, "killer": killer, "weapon": weapon, "headshot": headshot})


func _hit(_zone: int, killed: bool) -> void:
	hits.append(killed)


func _spawn(id: int) -> void:
	spawns.append(id)


func test_nonlethal_hit_then_lethal_headshot_emit_exact_server_metadata() -> void:
	actor.life.rules.downed_enabled = false
	actor.health_component.apply_damage(10.0, 1, HitboxZone.TORSO, &"pistol")
	assert_eq(hits, [false])
	assert_true(deaths.is_empty())
	_kill(1, HitboxZone.HEAD)
	assert_eq(hits, [false, true])
	assert_eq(deaths.size(), 1)
	assert_eq(deaths[0], {"victim": 42, "killer": 1, "weapon": &"sample_ar", "headshot": true})
	actor.health_component.apply_damage(1000.0, 1)
	assert_eq(deaths.size(), 1)
	assert_eq(hits.size(), 2)


func test_finisher_replaces_downing_killer_weapon_and_zone() -> void:
	actor.health_component.apply_damage(100.0, 9, HitboxZone.HEAD, &"rifle")
	assert_true(deaths.is_empty())
	actor.health_component.apply_damage(1.0, 1, HitboxZone.TORSO, &"knife")
	assert_eq(hits, [true])
	assert_eq(deaths[0]["killer"], 1)
	assert_eq(deaths[0]["weapon"], &"knife")
	assert_false(deaths[0]["headshot"])


func test_bleedout_preserves_downing_weapon_and_does_not_fake_a_second_hit() -> void:
	actor.health_component.apply_damage(100.0, 1, HitboxZone.HEAD, &"dmr")
	assert_eq(hits, [false])
	actor.life.step(actor.life.rules.bleedout_time)
	assert_eq(deaths.size(), 1)
	assert_eq(deaths[0]["weapon"], &"dmr")
	assert_true(deaths[0]["headshot"])
	assert_eq(hits, [false])


func test_environment_death_has_no_hit_confirmation_or_headshot() -> void:
	actor.life.rules.downed_enabled = false
	actor.health_component.apply_damage(1000.0)
	assert_true(hits.is_empty())
	assert_eq(deaths[0]["killer"], 0)
	assert_eq(deaths[0]["weapon"], &"")
	assert_false(deaths[0]["headshot"])


func test_respawn_event_once_and_protected_hits_emit_nothing() -> void:
	_kill()
	Net.tick = 280
	players.respawns.step(280)
	players.respawns.step(280)
	assert_eq(spawns, [42])
	actor.health_component.apply_damage(1000.0, 1, HitboxZone.HEAD, &"rifle")
	assert_eq(deaths.size(), 1)
	assert_eq(hits, [true])


func test_client_rpc_entry_points_and_unowned_ready_cannot_change_server() -> void:
	var before: Vector3 = actor.global_position
	players.combat_events.player_died(42, 9, &"fake", true)
	players.combat_events.hit_confirm(HitboxZone.HEAD, true)
	players.combat_events.damage_indicator(Vector3.UP)
	players.combat_events.player_spawned(42, Transform3D.IDENTITY, 1000, 100.0, 1120)
	players.combat_events.life_sync(42, 0.0, 100.0, PlayerLife.State.DEAD, 0.0, -1, 1000,
		Transform3D.IDENTITY, 1000)
	players.combat_events.actor_ready(42)
	assert_true(deaths.is_empty())
	assert_true(hits.is_empty())
	assert_true(spawns.is_empty())
	assert_eq(actor.health_component.current, 100.0)
	assert_eq(actor.global_position, before)


func test_late_replica_sync_restores_dead_state_and_spawn_is_atomic_and_idempotent() -> void:
	var api: SceneMultiplayer = SceneMultiplayer.new()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 1), OK)
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, loader.get_path())
	var events: CombatEvents = players.combat_events
	var pose: Transform3D = Transform3D(Basis.IDENTITY, Vector3(10, 0, 10))
	events.life_sync(42, 0.0, 100.0, PlayerLife.State.SPAWN_SELECT, 0.0, -1, 100, pose, 500)
	assert_eq(actor.life.state, PlayerLife.State.SPAWN_SELECT)
	assert_eq(actor.global_transform, pose)
	events.player_spawned(42, pose, 680, 100.0, 800)
	assert_eq(actor.life.state, PlayerLife.State.ALIVE)
	assert_eq(actor.health_component.current, 100.0)
	events.player_spawned(42, Transform3D.IDENTITY, 680, 100.0, 800)
	events.life_sync(42, 0.0, 100.0, PlayerLife.State.DEAD, 0.0, -1, 100, pose, 679)
	assert_eq(actor.life.state, PlayerLife.State.ALIVE)
	assert_eq(actor.global_transform, pose)
	assert_eq(spawns, [42, 42])
	peer.close()
	get_tree().set_multiplayer(null, loader.get_path())
