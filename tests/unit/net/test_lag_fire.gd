extends GutTest

var _lag: LagCompensator
var _target: Player
var _shooter: Player
var _old_tick: int
var _restored_at_damage: bool


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_old_tick = Net.tick
	_lag = LagCompensator.new()
	add_child_autofree(_lag)
	_lag.set_physics_process(false)
	_target = _actor(42, Vector3(500.0, 20.0, 490.0))
	_shooter = _actor(7, Vector3(500.0, 20.0, 500.0))
	_lag.track(_target)
	_lag.track(_shooter)
	_shooter.equipment.combat.lag_compensator = _lag
	_lag.record(90)
	_target.position.x += 3.0
	_restored_at_damage = false
	_shooter.weapon_hitscan.damage_applied.connect(_damaged)


func after_each() -> void:
	Net.tick = _old_tick


func _actor(id: int, pos: Vector3) -> Player:
	var actor: Player = preload("res://src/player/player.tscn").instantiate() as Player
	actor.network_owner_id = id
	actor.position = pos
	add_child_autofree(actor)
	actor.set_physics_process(false)
	return actor


func _damaged(_event: DamageEvent) -> void:
	_restored_at_damage = not _lag.active and _target.position.x == 503.0
	for index: int in range(_lag.tracks[0].zones.size()):
		var zone: HitboxZone = _lag.tracks[0].zones[index]
		_restored_at_damage = _restored_at_damage \
			and PhysicsServer3D.area_get_transform(zone.get_rid()) == zone.global_transform


func _request(viewed: int) -> void:
	Net.tick = 100
	var combat: NetworkCombat = _shooter.equipment.combat
	_shooter.server_sim.input_queue.last_input_tick = 105
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 100
	combat.simulate(inp, Transform3D(Basis.IDENTITY, Vector3(500.0, 21.0, 500.0)), false)
	assert_true(combat.history.request(105, FireHistory.shot_seed(105, 7), 7, 100, viewed))
	combat.history.slot(105).spread = 0.0
	combat._resolve(false)


func test_network_request_hits_history_and_restores_before_damage_signal() -> void:
	_request(90)
	assert_eq(_shooter.equipment.combat.accepted_shots, 1)
	assert_lt((_target.health_component as HealthComponent).current, 100.0)
	assert_true(_restored_at_damage)
	assert_false(_lag.active)
	assert_eq(_lag.last_rewind_tick, 90)


func test_miss_and_denied_shot_leave_no_rewind_active() -> void:
	_request(99)
	assert_eq(_shooter.equipment.combat.accepted_shots, 1)
	assert_eq((_target.health_component as HealthComponent).current, 100.0)
	assert_false(_lag.active)
	_shooter.weapon.ammo_in_mag = 0
	assert_false(_shooter.weapon_hitscan.fire_requested(100, 1, Transform3D.IDENTITY, 0.0))
	assert_false(_lag.active)


func test_host_view_uses_interpolation_delay_and_projectiles_never_rewind() -> void:
	Net.tick = 100
	_shooter.equipment.combat.interpolation_seconds = 0.1
	assert_eq(_shooter.equipment.combat.view_tick(), 94)
	_shooter.weapon_hitscan.lag_compensator = _lag
	var data: WeaponData = preload("res://src/weapons/data/launcher.tres").duplicate() as WeaponData
	_shooter.weapon.setup(data)
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 100
	_shooter.weapon_hitscan.simulate(inp, Transform3D.IDENTITY)
	assert_true(_shooter.weapon_hitscan.fire_requested(100, 1, Transform3D.IDENTITY, 0.0))
	assert_eq(_lag.last_rewind_tick, -1)
	assert_false(_lag.active)


func test_client_cannot_record_rewind_or_restore_server_history() -> void:
	var branch: Node = Node.new()
	add_child(branch)
	var api: SceneMultiplayer = SceneMultiplayer.new()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 1), OK)
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, branch.get_path())
	var lag: LagCompensator = LagCompensator.new()
	branch.add_child(lag)
	lag.track(_target)
	lag.record(100)
	assert_false(lag.rewind(100, 90, 7))
	assert_true(lag.tracks.is_empty())
	assert_false(lag.active)
	peer.close()
	get_tree().set_multiplayer(null, branch.get_path())
	branch.free()
