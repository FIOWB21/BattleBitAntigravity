extends GutTest

const ATTACKER: int = 17
const CONTACT_TICK: int = 13
const END_TICK: int = 43
const NEXT_TICK: int = 49
const HEIGHT: float = 1.125

var _world: Node3D
var _attack: MeleeAttack
var _target: TargetDummy
var _aim: Transform3D
var _hits: int = 0
var _backstab: bool = false
var _source: int = 0
var _starts: int = 0
var _finishes: int = 0


func _setup_rig(back: bool = false, distance: float = 1.0, health: float = 100.0) -> void:
	_hits = 0
	_starts = 0
	_finishes = 0
	_world = Node3D.new()
	_world.position = Vector3(1200.0, 30.0, 1200.0)
	add_child_autofree(_world)
	_attack = MeleeAttack.new()
	_world.add_child(_attack)
	_attack.setup(ATTACKER, [])
	_attack.attack_started.connect(func() -> void: _starts += 1)
	_attack.attack_finished.connect(func() -> void: _finishes += 1)
	_attack.hit_landed.connect(func(_health: HealthComponent, _damage: float, backstab: bool) -> void:
		_hits += 1
		_backstab = backstab)
	_target = load("res://src/maps/testbed/target_dummy.tscn").instantiate() as TargetDummy
	_target.position.z = -distance
	_target.rotation.y = 0.0 if back else PI
	_target.max_health = health
	_world.add_child(_target)
	_target.set_physics_process(false)
	_target.health_component.damaged.connect(func(_amount: float, source: int, _zone: int) -> void:
		_source = source)
	_aim = Transform3D(Basis.IDENTITY, _world.global_position + Vector3.UP * HEIGHT)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _step(tick: int, pressed: bool = false, alive: bool = true, allowed: bool = true) -> void:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = tick
	inp.melee = pressed
	_attack.simulate(inp, _aim, _world.global_position, alive, allowed)


func test_face_hit_waits_for_contact_and_deals_fifty_once() -> void:
	await _setup_rig()
	_step(1, true)
	_step(CONTACT_TICK - 1)
	assert_eq(_target.health_component.current, 100.0)
	_step(CONTACT_TICK)
	assert_eq(_target.health_component.current, 50.0)
	assert_false(_target.is_dead)
	assert_false(_backstab)
	assert_eq(_source, ATTACKER)
	_step(CONTACT_TICK)
	_step(CONTACT_TICK - 1)
	_step(END_TICK)
	assert_eq(_hits, 1)
	assert_eq(_starts, 1)
	assert_eq(_finishes, 1)
	assert_false(_attack.busy)
	print("ACCEPT 2.11: face hit = 50 damage, delayed 12 ticks, one contact")


func test_back_hit_kills_even_high_health_without_head_multiplier() -> void:
	await _setup_rig(true, 1.0, 500.0)
	_step(1, true)
	_step(CONTACT_TICK)
	assert_true(_target.is_dead)
	assert_eq(_target.health_component.current, 0.0)
	assert_true(_backstab)
	assert_eq(_hits, 1)
	assert_eq(_source, ATTACKER)
	print("ACCEPT 2.11: back hit = lethal (500 HP), source=17")


func test_head_hit_from_front_uses_same_fixed_damage() -> void:
	await _setup_rig()
	_aim.origin.y = _world.global_position.y + 1.65
	_step(1, true)
	_step(CONTACT_TICK)
	assert_eq(_target.health_component.current, 50.0)
	assert_false(_backstab)


func test_rear_cone_uses_relative_position_and_target_rotation() -> void:
	var data: MeleeData = load("res://src/weapons/data/knife.tres") as MeleeData
	for angle: float in [0.0, PI * 0.5, PI, -PI * 0.5]:
		var target: Transform3D = Transform3D(Basis(Vector3.UP, angle), Vector3(50.0, 8.0, -20.0))
		assert_true(data.is_backstab(target.origin + target.basis.z * 2.0 + Vector3.UP * 9.0, target))
		assert_false(data.is_backstab(target.origin - target.basis.z, target))
		assert_false(data.is_backstab(target.origin + target.basis.x, target))
		assert_false(data.is_backstab(target.origin, target))
		assert_true(data.is_backstab(target.origin + target.basis * Vector3(0.8, 0.0, 1.0), target))
		assert_false(data.is_backstab(target.origin + target.basis * Vector3(2.0, 0.0, 1.0), target))


func test_ray_reaches_near_surface_but_cannot_hit_beyond_one_point_five() -> void:
	await _setup_rig(false, 1.63)
	_step(1, true)
	_step(CONTACT_TICK)
	assert_eq(_hits, 1)
	_target.position.z = -1.7
	await get_tree().physics_frame
	await get_tree().physics_frame
	_step(NEXT_TICK, true)
	_step(NEXT_TICK + CONTACT_TICK - 1)
	assert_eq(_hits, 1)
	assert_eq(_target.health_component.current, 50.0)


func test_world_wall_blocks_knife() -> void:
	await _setup_rig(true)
	var wall: StaticBody3D = StaticBody3D.new()
	wall.position = Vector3(0.0, HEIGHT, -0.5)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(2.0, 3.0, 0.05)
	shape.shape = box
	wall.add_child(shape)
	_world.add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_step(1, true)
	_step(CONTACT_TICK)
	assert_eq(_hits, 0)
	assert_eq(_target.health_component.current, 100.0)


func test_impact_uses_current_aim_and_does_not_lock_target_at_start() -> void:
	await _setup_rig(true)
	_step(1, true)
	_aim.basis = Basis(Vector3.UP, PI)
	_step(CONTACT_TICK)
	assert_eq(_hits, 0)
	assert_false(_target.is_dead)


func test_target_turning_during_windup_changes_backstab_result() -> void:
	await _setup_rig(true)
	_step(1, true)
	_target.rotation.y = PI
	await get_tree().physics_frame
	await get_tree().physics_frame
	_step(CONTACT_TICK)
	assert_eq(_hits, 1)
	assert_false(_backstab)
	assert_eq(_target.health_component.current, 50.0)


func test_cooldown_rejects_early_commands_and_does_not_queue_them() -> void:
	await _setup_rig(false, 1.0, 500.0)
	_step(1, true)
	for tick: int in range(2, NEXT_TICK):
		_step(tick, true)
	assert_eq(_starts, 1)
	assert_eq(_hits, 1)
	_step(NEXT_TICK)
	assert_eq(_starts, 1)
	_step(NEXT_TICK + 1, true)
	_step(NEXT_TICK + CONTACT_TICK)
	assert_eq(_starts, 2)
	assert_eq(_hits, 2)


func test_death_cancels_contact_and_blocked_start_does_not_consume_attack() -> void:
	await _setup_rig()
	_step(1, true, true, false)
	assert_false(_attack.busy)
	_step(2, true)
	assert_true(_attack.busy)
	_step(CONTACT_TICK + 1, false, false)
	assert_false(_attack.busy)
	assert_eq(_hits, 0)
	assert_eq(_finishes, 1)


func test_skipped_ticks_resolve_contact_once_and_finish() -> void:
	await _setup_rig()
	_step(1, true)
	_step(100)
	_step(101)
	assert_eq(_hits, 1)
	assert_eq(_finishes, 1)
	assert_false(_attack.busy)


func test_excluded_hitboxes_are_ignored() -> void:
	await _setup_rig()
	_attack.setup(ATTACKER, _target.hitboxes.get_exclude_rids())
	_step(1, true)
	_step(CONTACT_TICK)
	assert_eq(_hits, 0)
	assert_eq(_target.health_component.current, 100.0)


func test_client_cannot_start_or_damage() -> void:
	await _setup_rig(true)
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 9), OK)
	api.multiplayer_peer = peer
	var path: NodePath = _world.get_path()
	get_tree().set_multiplayer(api, path)
	_step(1, true)
	_step(CONTACT_TICK)
	assert_eq(_hits, 0)
	assert_eq(_starts, 0)
	assert_false(_attack.busy)
	assert_false(_target.is_dead)
	get_tree().set_multiplayer(null, path)
	peer.close()
