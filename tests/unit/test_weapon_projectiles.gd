extends GutTest

var _world: Node3D
var _system: ProjectileSystem
var _weapon: Weapon
var _driver: WeaponHitscan
var _target: TargetDummy
var _traces: int = 0


func before_each() -> void:
	_traces = 0
	_world = Node3D.new()
	_world.position = Vector3(1100.0, 40.0, 1100.0)
	add_child_autofree(_world)
	_system = ProjectileSystem.new()
	_system.capacity = 1
	_world.add_child(_system)
	_system.set_physics_process(false)
	_weapon = Weapon.new()
	_weapon.data = load("res://src/weapons/data/launcher.tres").duplicate() as WeaponData
	_weapon.data.spread_hip_deg = 0.0
	_world.add_child(_weapon)
	_driver = WeaponHitscan.new()
	_world.add_child(_driver)
	_driver.setup(_weapon, 42, [])
	_driver.projectiles = _system
	_driver.shot_traced.connect(func(_tick: int, _pellet: int, _direction: Vector3, _hit: HitResult) -> void:
		_traces += 1)
	_target = load("res://src/maps/testbed/target_dummy.tscn").instantiate() as TargetDummy
	_target.max_health = 1000.0
	_target.position = Vector3(0.0, 0.0, -10.0)
	_world.add_child(_target)
	_target.health_component.reset()
	_target.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _step(tick: int, fire: bool) -> void:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = tick
	inp.buttons = PlayerInput.BTN_FIRE if fire else 0
	_driver.simulate(inp, Transform3D(Basis.IDENTITY, _world.global_position + Vector3.UP * 1.125))


func test_launcher_fired_consumes_one_round_launches_same_projectile_and_defers_damage() -> void:
	_step(0, true)
	assert_eq(_weapon.ammo_in_mag, 0)
	assert_true(_system.projectiles[0].active)
	assert_eq(_system.projectiles[0].data.kind, ProjectileData.Kind.ROCKET)
	assert_eq(_target.health_component.current, 1000.0)
	assert_eq(_traces, 0)
	assert_gt(_driver.handling.recoil_deg.length(), 0.0)
	for tick: int in range(8):
		_system.advance(1.0 / 60.0)
	assert_false(_system.projectiles[0].active)
	assert_lt(_target.health_component.current, 1000.0)
	assert_eq(_weapon.ammo_in_mag, 0)
	assert_eq(_traces, 0)


func test_launcher_pool_backpressure_blocks_fire_without_consuming_ammo() -> void:
	var smoke: ProjectileData = load("res://src/weapons/projectiles/smoke.tres") as ProjectileData
	var grenade: Projectile = _system.launch(smoke, _world.global_position, Vector3.ZERO)
	_step(0, true)
	assert_eq(_weapon.ammo_in_mag, 1)
	assert_eq(_weapon.state, Weapon.State.BLOCKED)
	assert_eq(grenade.data, smoke)
	_system.advance(3.0)
	_step(1, false)
	_step(2, true)
	assert_eq(_weapon.ammo_in_mag, 0)
	assert_true(grenade.active)
	assert_eq(grenade.data.kind, ProjectileData.Kind.ROCKET)
	assert_eq(_traces, 0)
