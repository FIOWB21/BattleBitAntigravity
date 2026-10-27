extends GutTest

const STEP: float = 1.0 / 60.0
var _world: Node3D
var _system: ProjectileSystem
var _count: int = 0
var _bounces: int = 0


func before_each() -> void:
	_count = 0
	_bounces = 0
	_world = Node3D.new()
	_world.position = Vector3(700.0, 30.0, 700.0)
	add_child_autofree(_world)
	_system = ProjectileSystem.new()
	_system.capacity = 2
	_world.add_child(_system)
	_system.set_physics_process(false)
	_system.exploded.connect(func(_data: ProjectileData, _point: Vector3, _source: int) -> void:
		_count += 1)


func _profile(name: String = "frag") -> ProjectileData:
	return load("res://src/weapons/projectiles/%s.tres" % name).duplicate() as ProjectileData


func _wall(offset: Vector3, size: Vector3) -> StaticBody3D:
	var wall: StaticBody3D = StaticBody3D.new()
	wall.position = offset
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	collision.shape = box
	wall.add_child(collision)
	_world.add_child(wall)
	return wall


func _target(offset: Vector3) -> TargetDummy:
	var target: TargetDummy = load("res://src/maps/testbed/target_dummy.tscn").instantiate() as TargetDummy
	target.position = offset
	target.max_health = 1000.0
	_world.add_child(target)
	target.health_component.reset()
	target.set_physics_process(false)
	return target


func _sync() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func test_fuse_is_exactly_three_seconds_and_emits_only_once() -> void:
	var grenade: Projectile = _system.launch(_profile(), _world.global_position, Vector3.ZERO, 77)
	for tick: int in range(179):
		_system.advance(STEP)
	assert_true(grenade.active)
	assert_eq(_count, 0)
	_system.advance(STEP)
	assert_false(grenade.active)
	assert_eq(_count, 1)
	assert_eq(grenade.age, 3.0)
	_system.advance(10.0)
	assert_eq(_count, 1)


func test_large_delta_clamps_motion_to_fuse_and_invalid_delta_is_ignored() -> void:
	var data: ProjectileData = _profile()
	data.drag = 0.0
	var initial: Vector3 = Vector3(2.0, 5.0, 0.0)
	var grenade: Projectile = _system.launch(data, _world.global_position, initial)
	for invalid: float in [0.0, -1.0, INF, NAN]:
		grenade.simulate(invalid)
	assert_eq(grenade.age, 0.0)
	grenade.simulate(10.0)
	assert_almost_eq(grenade.global_position, _world.global_position +
		ProjectileBallistics.displacement(initial, data, 3.0), 0.0001)
	assert_eq(_count, 1)


func test_grenade_sweeps_thin_wall_bounces_and_keeps_remaining_time() -> void:
	_wall(Vector3(2.0, 0.0, 0.0), Vector3(0.02, 8.0, 8.0))
	await _sync()
	var data: ProjectileData = _profile()
	data.drag = 0.0
	var grenade: Projectile = _system.launch(data, _world.global_position, Vector3(300.0, 0.0, 0.0))
	grenade.bounced.connect(func(_point: Vector3, _normal: Vector3) -> void: _bounces += 1)
	grenade.simulate(STEP)
	assert_eq(_bounces, 1)
	assert_lt(grenade.velocity.x, 0.0)
	assert_lt(grenade.global_position.x - _world.global_position.x, 1.0)
	assert_lt(grenade.global_position.y, _world.global_position.y)
	assert_true(grenade.active)


func test_resting_grenade_keeps_fuse_and_does_not_sink_into_floor() -> void:
	_wall(Vector3(0.0, -0.5, 0.0), Vector3(10.0, 1.0, 10.0))
	await _sync()
	var data: ProjectileData = _profile()
	data.restitution = 0.0
	var grenade: Projectile = _system.launch(data, _world.global_position + Vector3.UP, Vector3.DOWN)
	for tick: int in range(120):
		grenade.simulate(STEP)
	assert_true(grenade.resting)
	assert_almost_eq(grenade.global_position.y - _world.global_position.y, data.contact_offset, 0.001)
	assert_true(grenade.active)
	for tick: int in range(60):
		grenade.simulate(STEP)
	assert_eq(_count, 1)


func test_explosion_deduplicates_hitboxes_has_falloff_and_wall_occlusion() -> void:
	var near_target: TargetDummy = _target(Vector3.ZERO)
	var far_target: TargetDummy = _target(Vector3(4.0, 0.0, 0.0))
	var hidden_target: TargetDummy = _target(Vector3(-4.0, 0.0, 0.0))
	_wall(Vector3(-2.0, 1.0, 0.0), Vector3(0.2, 4.0, 4.0))
	await _sync()
	var origin: Vector3 = near_target.hitboxes.torso_zone.global_position
	var data: ProjectileData = _profile()
	_system.explosion.apply(data, origin, 42)
	assert_almost_eq(near_target.health_component.current, 850.0, 0.001)
	assert_almost_eq(far_target.health_component.current, 925.0, 0.001)
	assert_eq(hidden_target.health_component.current, 1000.0)
	print("ACCEPT 2.10: real hitboxes center=150 half=75 behind wall=0; no duplicate damage")


func test_rocket_detonates_on_wall_on_same_projectile_and_never_tunnels() -> void:
	_wall(Vector3(2.0, 0.0, 0.0), Vector3(0.02, 10.0, 10.0))
	await _sync()
	var rocket: Projectile = _system.launch(_profile("rocket"), _world.global_position, Vector3(300.0, 0.0, 0.0))
	rocket.simulate(STEP)
	assert_false(rocket.active)
	assert_eq(_count, 1)
	assert_almost_eq(rocket.global_position.x - _world.global_position.x, 1.98, 0.002)
	assert_lt(rocket.age, rocket.data.fuse)


func test_pool_exhaustion_keeps_active_projectiles_then_reuses_inactive_object() -> void:
	var first: Projectile = _system.launch(_profile(), _world.global_position, Vector3.ZERO)
	var second: Projectile = _system.launch(_profile(), _world.global_position, Vector3.ZERO)
	var nodes: int = get_tree().get_node_count()
	assert_null(_system.launch(_profile(), _world.global_position, Vector3.ZERO))
	assert_true(first.active)
	assert_true(second.active)
	first.simulate(3.0)
	assert_eq(_system.launch(_profile("smoke"), _world.global_position, Vector3.RIGHT), first)
	assert_eq(first.age, 0.0)
	assert_false(first.resting)
	assert_eq(get_tree().get_node_count(), nodes)


func test_smoke_and_flash_detonate_without_applying_gameplay_damage() -> void:
	var target: TargetDummy = _target(Vector3.ZERO)
	await _sync()
	for name: String in ["smoke", "flash"]:
		var grenade: Projectile = _system.launch(_profile(name),
			target.hitboxes.torso_zone.global_position, Vector3.ZERO)
		grenade.resting = true
		grenade.simulate(10.0)
	assert_eq(_count, 2)
	assert_eq(target.health_component.current, 1000.0)


func test_network_client_cannot_launch_simulate_or_apply_explosion_damage() -> void:
	var target: TargetDummy = _target(Vector3.ZERO)
	await _sync()
	var data: ProjectileData = _profile()
	var grenade: Projectile = _system.launch(data, _world.global_position, Vector3.RIGHT)
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 9), OK)
	api.multiplayer_peer = peer
	var path: NodePath = _system.get_path()
	get_tree().set_multiplayer(api, path)
	assert_null(_system.launch(data, _world.global_position, Vector3.ZERO))
	grenade.simulate(10.0)
	_system.explosion.apply(data, target.hitboxes.torso_zone.global_position, 42)
	assert_true(grenade.active)
	assert_eq(grenade.age, 0.0)
	assert_eq(target.health_component.current, 1000.0)
	assert_eq(_count, 0)
	get_tree().set_multiplayer(null, path)
	peer.close()


func test_invalid_launch_does_not_consume_pool_or_activate_projectile() -> void:
	var origin: Vector3 = _world.global_position
	assert_null(_system.launch(null, origin, Vector3.ZERO))
	var data: ProjectileData = _profile()
	data.fuse = 0.0
	assert_null(_system.launch(data, origin, Vector3.ZERO))
	data.fuse = INF
	assert_null(_system.launch(data, origin, Vector3.ZERO))
	data.fuse = 3.0
	assert_null(_system.launch(data, origin, Vector3(INF, 0.0, 0.0)))
	assert_false(_system.projectiles[0].active)
	assert_false(_system.projectiles[1].active)


func test_excluded_body_does_not_bounce_and_rocket_hits_real_hitbox() -> void:
	var wall: StaticBody3D = _wall(Vector3(1.0, 0.0, 0.0), Vector3(0.02, 5.0, 5.0))
	var target: TargetDummy = _target(Vector3(3.0, -1.125, 0.0))
	await _sync()
	var excluded: Array[RID] = [wall.get_rid()]
	var rocket: Projectile = _system.launch(_profile("rocket"), _world.global_position,
		Vector3(300.0, 0.0, 0.0), 12, excluded)
	rocket.simulate(STEP)
	assert_false(rocket.active)
	assert_gt(rocket.global_position.x - _world.global_position.x, 2.0)
	assert_lt(target.health_component.current, 1000.0)


func test_contact_budget_stays_inside_corridor_and_pool_reuse_is_bounded() -> void:
	_wall(Vector3(1.0, 0.0, 0.0), Vector3(0.02, 5.0, 5.0))
	_wall(Vector3(-1.0, 0.0, 0.0), Vector3(0.02, 5.0, 5.0))
	await _sync()
	var data: ProjectileData = _profile("smoke")
	data.max_contacts = 1
	data.gravity = Vector3.ZERO
	data.drag = 0.0
	data.fuse = STEP
	var first: Projectile = _system.projectiles[0]
	var second: Projectile = _system.projectiles[1]
	var nodes: int = get_tree().get_node_count()
	for tick: int in range(300):
		var grenade: Projectile = _system.launch(data, _world.global_position, Vector3(600.0, 0.0, 0.0))
		grenade.simulate(STEP)
		assert_lt(absf(grenade.global_position.x - _world.global_position.x), 1.0)
		assert_false(grenade.active)
	assert_eq(_count, 300)
	assert_eq(_system.projectiles[0], first)
	assert_eq(_system.projectiles[1], second)
	assert_eq(get_tree().get_node_count(), nodes)
