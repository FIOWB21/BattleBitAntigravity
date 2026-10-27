# Проверяет каждый профиль на настоящем полигоне либо запускает выбранный для плейтеста.
extends SceneTree

const CATALOG_PATH: String = "res://src/weapons/data/balanced_catalog.tres"
const TEST_ORIGIN: Vector3 = Vector3(-30.0, 1.125, -30.0)
const TEST_TARGET: Vector3 = Vector3(-30.0, 0.0, -40.0)
const TARGET_HEALTH: float = 1000.0

var _world: Node3D
var _weapon: Weapon
var _driver: WeaponHitscan
var _target: TargetDummy
var _fired: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 120
	var catalog: WeaponCatalog = load(CATALOG_PATH) as WeaponCatalog
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--weapon="):
			_play(catalog, arg.trim_prefix("--weapon="))
			return
	var checked: int = 0
	for data: WeaponData in catalog.weapons:
		var success: bool = await _check_profile(data)
		await _cleanup()
		if not success:
			printerr("BALANCE ACCEPTANCE FAIL: ", data.id)
			quit(1)
			return
		checked += 1
	print("BALANCE ACCEPTANCE OK: profiles=", checked)
	quit(0)


func _play(catalog: WeaponCatalog, id: String) -> void:
	for data: WeaponData in catalog.weapons:
		if String(data.id) == id:
			_spawn_world(data)
			print("BALANCE PLAYTEST: ", data.id, " source=", data.resource_path)
			return
	printerr("Unknown weapon ID: ", id)
	quit(1)


func _spawn_world(data: WeaponData) -> void:
	_world = load("res://src/maps/testbed/testbed.tscn").instantiate() as Node3D
	_weapon = _world.get_node("Player/Weapon") as Weapon
	_weapon.data = data
	var inventory: Inventory = _world.get_node("Player/Inventory") as Inventory
	var loadout: Loadout = Loadout.new()
	loadout.primary = data
	inventory.loadout = loadout
	root.add_child(_world)
	current_scene = _world
	_driver = _world.get_node("Player/WeaponHitscan") as WeaponHitscan


func _check_profile(data: WeaponData) -> bool:
	_spawn_world(data)
	for node: Node in _world.find_children("*", "", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	_world.get_node("Player").call("release_mouse")
	_target = load("res://src/maps/testbed/target_dummy.tscn").instantiate() as TargetDummy
	_target.position = TEST_TARGET
	_target.max_health = TARGET_HEALTH
	_world.add_child(_target)
	_target.health_component.reset()
	_target.set_physics_process(false)
	await physics_frame
	await physics_frame
	_fired = 0
	_weapon.fired.connect(func(_tick: int) -> void: _fired += 1)
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 0
	inp.buttons = PlayerInput.BTN_FIRE | PlayerInput.BTN_AIM
	_driver.simulate(inp, Transform3D(Basis.IDENTITY, TEST_ORIGIN), false,
		PlayerStance.STAND, 0.0, false, 1.0)
	if data.projectile_data != null:
		for tick: int in range(60):
			_driver.projectiles.advance(1.0 / Engine.physics_ticks_per_second)
	var damage: float = TARGET_HEALTH - _target.health_component.current
	print("BALANCE SHOT: id=", data.id, " fired=", _fired, " damage=", damage,
		" ammo=", _weapon.ammo_in_mag, " projectile=", data.projectile_data != null)
	return _fired == 1 and _weapon.ammo_in_mag == data.mag_size - 1 and damage > 0.0


func _cleanup() -> void:
	_world.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.05).timeout
