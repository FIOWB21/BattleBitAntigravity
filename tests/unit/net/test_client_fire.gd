extends GutTest

var _branch: Node3D
var _api: SceneMultiplayer
var _weapon: Weapon
var _hitscan: WeaponHitscan
var _health: HealthComponent
var _traces: int = 0
var _damage: int = 0


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_branch = Node3D.new()
	add_child(_branch)
	_api = SceneMultiplayer.new()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 1), OK)
	_api.multiplayer_peer = peer
	get_tree().set_multiplayer(_api, _branch.get_path())
	_weapon = Weapon.new()
	_weapon.data = WeaponData.new()
	_branch.add_child(_weapon)
	_hitscan = WeaponHitscan.new()
	_branch.add_child(_hitscan)
	_hitscan.setup(_weapon, 7, [])
	_hitscan.shot_traced.connect(_traced)
	_hitscan.damage_applied.connect(_damaged)
	_health = HealthComponent.new()
	_branch.add_child(_health)
	_traces = 0
	_damage = 0


func after_each() -> void:
	_api.multiplayer_peer.close()
	get_tree().set_multiplayer(null, _branch.get_path())
	_branch.free()
	await get_tree().process_frame


func _traced(_tick: int, _pellet: int, _direction: Vector3, _hit: HitResult) -> void:
	_traces += 1


func _damaged(_event: DamageEvent) -> void:
	_damage += 1


func test_cosmetic_shot_traces_immediately_without_server_simulation_or_damage() -> void:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 100
	inp.buttons = PlayerInput.BTN_FIRE
	_hitscan.simulate(inp, Transform3D.IDENTITY)
	assert_eq(_traces, 0)
	_hitscan.cosmetic_only = true
	_hitscan.simulate(inp, Transform3D.IDENTITY)
	assert_eq(_traces, 1)
	assert_eq(_damage, 0)
	assert_false(_weapon.fire_requested(100))
	assert_false(_hitscan.fire_requested(100, 123, Transform3D.IDENTITY, 0.0))


func test_even_fabricated_client_hit_result_cannot_apply_damage() -> void:
	var hit: HitResult = HitResult.new()
	hit.hit = true
	hit.health_component = _health
	_hitscan.cosmetic_only = true
	_hitscan._apply_hit(_weapon.data, hit)
	assert_eq(_health.current, _health.max_health)
	assert_eq(_damage, 0)


func test_server_sync_restores_equipped_state_after_holstering() -> void:
	_weapon.sync_replica(Weapon.State.SWITCHING_OUT, 100, 0, 0, 5)
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 105
	_weapon.simulate_cosmetic(inp, false, false)
	assert_eq(_weapon.state, Weapon.State.BLOCKED)
	_weapon.sync_replica(Weapon.State.IDLE, 106, 0, 0, 0)
	inp.tick = 106
	inp.buttons = PlayerInput.BTN_FIRE
	_weapon.simulate_cosmetic(inp, false, false)
	assert_eq(_weapon.ammo_in_mag, _weapon.data.mag_size - 1)


func test_server_sync_keeps_predicted_cooldown_and_authoritative_reload_deadline() -> void:
	_weapon.next_fire_tick = 120
	_weapon.sync_replica(Weapon.State.RELOADING, 100, 2, 30, 0)
	assert_eq(_weapon.next_fire_tick, 120)
	assert_eq(_weapon.reload_end_tick, 130)
	assert_eq(_weapon.switch_end_tick, -1)
