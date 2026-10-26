extends GutTest

const ATTACKER: int = 7
const TORSO_HEIGHT: float = 1.125
const HEAD_HEIGHT: float = 1.65
const EPSILON: float = 0.001

var _world: Node3D
var _weapon: Weapon
var _hitscan: WeaponHitscan
var _target: TargetDummy
var _events: Array[DamageEvent] = []
var _directions: Array[Vector3] = []
var _hits: Array[HitResult] = []


func before_each() -> void:
	_events.clear()
	_directions.clear()
	_hits.clear()


func _setup_rig(profile: String = "ar", distance: float = 10.0, health: float = 100.0) -> void:
	_world = Node3D.new()
	_world.position = Vector3(500.0, 20.0, 500.0)
	add_child_autofree(_world)
	_weapon = Weapon.new()
	_weapon.data = load("res://src/weapons/data/" + profile + ".tres").duplicate() as WeaponData
	_weapon.data.spread_hip_deg = 0.0
	_world.add_child(_weapon)
	_hitscan = WeaponHitscan.new()
	_world.add_child(_hitscan)
	_hitscan.setup(_weapon, ATTACKER, [])
	_hitscan.damage_applied.connect(func(event: DamageEvent) -> void: _events.append(event))
	_hitscan.shot_traced.connect(
		func(_tick: int, _pellet: int, direction: Vector3, hit: HitResult) -> void:
			_directions.append(direction)
			_hits.append(hit))
	_target = (load("res://src/maps/testbed/target_dummy.tscn") as PackedScene).instantiate() as TargetDummy
	_target.position = Vector3(0.0, 0.0, -distance)
	_target.max_health = health
	_world.add_child(_target)
	_target.health_component.reset()
	_target.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _fire(tick: int, height: float = TORSO_HEIGHT, basis: Basis = Basis.IDENTITY) -> void:
	var inp: PlayerInput = PlayerInput.new()
	var aim: Transform3D = Transform3D(basis, _world.global_position + Vector3(0.0, height, 0.0))
	inp.tick = tick - 1
	_hitscan.simulate(inp, aim)
	inp.tick = tick
	inp.buttons = PlayerInput.BTN_FIRE
	_hitscan.simulate(inp, aim)


func test_ar_at_ten_meters_kills_torso_in_four_hits_and_records_event() -> void:
	await _setup_rig()
	for shot: int in range(3):
		_fire(shot * 60)
		assert_false(_target.is_dead)
	assert_almost_eq(_target.health_component.current, 10.0, EPSILON)
	_fire(180)
	assert_true(_target.is_dead)
	assert_false(_target.visuals.visible)
	assert_eq(_events.size(), 4)
	var event: DamageEvent = _events[0]
	assert_eq(event.attacker, ATTACKER)
	assert_eq(event.target, _target)
	assert_eq(event.zone, HitboxZone.TORSO)
	assert_eq(event.weapon, &"sample_ar")
	assert_almost_eq(event.damage, 30.0, EPSILON)
	assert_almost_eq(event.distance, 9.86, 0.02)
	assert_almost_eq(event.point, _hits[0].point, EPSILON)
	print("ACCEPT 2.3: AR 10m torso = 4 hits (30 damage each)")


func test_ar_at_ten_meters_kills_head_in_two_hits() -> void:
	await _setup_rig()
	_fire(0, HEAD_HEIGHT)
	assert_almost_eq(_target.health_component.current, 40.0, EPSILON)
	_fire(60, HEAD_HEIGHT)
	assert_true(_target.is_dead)
	assert_eq(_events.size(), 2)
	assert_eq(_events[0].zone, HitboxZone.HEAD)
	assert_eq(_events[0].damage, 60.0)
	print("ACCEPT 2.3: AR 10m head = 2 hits (60 damage each)")


func test_shotgun_traces_all_pellets_and_sums_damage_for_one_shell() -> void:
	await _setup_rig("shotgun", 5.0, 500.0)
	_fire(0)
	assert_eq(_directions.size(), 8)
	assert_eq(_events.size(), 8)
	assert_eq(_weapon.ammo_in_mag, 7)
	var total: float = 0.0
	for event: DamageEvent in _events:
		total += event.damage
	assert_almost_eq(total, 96.0, EPSILON)
	assert_almost_eq(_target.health_component.current, 404.0, EPSILON)
	print("ACCEPT 2.3: shotgun 5m = 8 pellets, 96 total damage, 1 shell")


func test_world_blocks_damage_and_misses_do_not_damage() -> void:
	await _setup_rig()
	var wall: StaticBody3D = StaticBody3D.new()
	wall.position = Vector3(0.0, TORSO_HEIGHT, -5.0)
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 0.2)
	shape_node.shape = box
	wall.add_child(shape_node)
	_world.add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_fire(0)
	assert_eq(_hits[0].collider, wall)
	assert_eq(_events.size(), 0)
	_fire(60, TORSO_HEIGHT, Basis(Vector3.UP, PI))
	assert_false(_hits[1].hit)
	assert_eq(_target.health_component.current, 100.0)


func test_shotgun_spread_hits_close_torso_with_all_pellets() -> void:
	await _setup_rig("shotgun", 1.0)
	_weapon.data.spread_hip_deg = 5.0
	_fire(0)
	assert_eq(_directions.size(), 8)
	assert_eq(_events.size(), 8)
	assert_eq(_target.health_component.current, 4.0)
	assert_false(_target.is_dead)


func test_range_limit_and_real_impact_distance_control_damage() -> void:
	await _setup_rig("ar", 100.0)
	_weapon.data.hitscan_range = 50.0
	_fire(0)
	assert_false(_hits[0].hit)
	assert_eq(_events.size(), 0)
	_weapon.data.hitscan_range = 150.0
	_fire(60)
	assert_almost_eq(_events[0].distance, 99.86, 0.02)
	assert_eq(_events[0].damage, 18.0)
	assert_eq(_target.health_component.current, 82.0)


func test_spread_is_repeatable_bounded_and_varies_between_pellets() -> void:
	await _setup_rig("shotgun")
	_weapon.data.spread_hip_deg = 5.0
	_fire(0)
	var first: Array[Vector3] = _directions.duplicate()
	for direction: Vector3 in first:
		assert_almost_eq(direction.length(), 1.0, EPSILON)
		assert_true(direction.angle_to(Vector3.FORWARD) <= deg_to_rad(5.0) + EPSILON)
	assert_ne(first[0], first[1])
	_weapon.setup(_weapon.data)
	_directions.clear()
	_fire(0)
	assert_eq(_directions, first)
	_directions.clear()
	_fire(60)
	assert_ne(_directions, first)


func test_repeated_ticks_and_blocked_fire_never_trace_extra_rays() -> void:
	await _setup_rig()
	_hitscan.setup(_weapon, ATTACKER, [])
	_fire(0)
	_fire(0)
	assert_eq(_directions.size(), 1)
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 60
	inp.buttons = PlayerInput.BTN_FIRE
	_hitscan.simulate(inp, Transform3D.IDENTITY, true)
	assert_eq(_directions.size(), 1)
	assert_eq(_weapon.ammo_in_mag, 29)


func test_excludes_shooter_hitboxes_and_preserves_shooter_health() -> void:
	await _setup_rig()
	var shooter: Player = (load("res://src/player/player.tscn") as PackedScene).instantiate() as Player
	shooter.is_local_player = false
	shooter.position.z = -1.0
	_world.add_child(shooter)
	_hitscan.setup(_weapon, ATTACKER, shooter.get_hitscan_exclude_rids())
	await get_tree().physics_frame
	await get_tree().physics_frame
	_fire(0)
	assert_eq(_events[0].target, _target)
	assert_eq((shooter.health_component as HealthComponent).current, 100.0)
	assert_eq(_target.health_component.current, 70.0)


func test_client_cannot_trace_or_apply_even_a_direct_fired_signal() -> void:
	await _setup_rig()
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 9), OK)
	api.multiplayer_peer = peer
	var path: NodePath = _world.get_path()
	get_tree().set_multiplayer(api, path)
	_fire(0)
	_weapon.fired.emit(0)
	assert_eq(_events.size(), 0)
	assert_eq(_directions.size(), 0)
	assert_eq(_weapon.ammo_in_mag, 30)
	assert_eq(_target.health_component.current, 100.0)
	get_tree().set_multiplayer(null, path)
	peer.close()


func test_player_input_fires_at_target_on_testbed_without_render_camera() -> void:
	var bed: Node3D = (load("res://src/maps/testbed/testbed.tscn") as PackedScene).instantiate() as Node3D
	var player: Player = bed.get_node("Player") as Player
	player.is_local_player = false
	player.position = Vector3(40.0, 0.05, 50.0)
	var target: TargetDummy = bed.get_node("Targets/TargetDummy_01") as TargetDummy
	target.position = Vector3(40.0, 0.0, 40.0)
	add_child_autofree(bed)
	player.weapon.setup(player.weapon.data.duplicate() as WeaponData)
	player.weapon.data.spread_hip_deg = 0.0
	var inp: PlayerInput = PlayerInput.new()
	for tick: int in range(15):
		await get_tree().physics_frame
		inp.tick = tick
		player.step_simulation(inp, 1.0 / 60.0)
	assert_true(player.is_on_floor())
	inp.pitch = -atan2(player.head.global_position.y - TORSO_HEIGHT, 10.0)
	inp.buttons = PlayerInput.BTN_FIRE
	for shot: int in range(4):
		inp.tick = 30 + shot * 60
		player.step_simulation(inp, 1.0 / 60.0)
	assert_true(target.is_dead)
	assert_eq(player.weapon.ammo_in_mag, 26)
	assert_eq((player.health_component as HealthComponent).current, 100.0)
	print("ACCEPT 2.3: testbed PlayerInput -> Weapon.fired -> target died")
