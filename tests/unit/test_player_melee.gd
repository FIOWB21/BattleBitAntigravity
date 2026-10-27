extends GutTest

var _player: Player
var _target: TargetDummy


func _setup_player(local: bool = true) -> void:
	_player = load("res://src/player/player.tscn").instantiate() as Player
	_player.is_local_player = local
	_player.position = Vector3(1400.0, 30.0, 1400.0)
	add_child_autofree(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	_player.release_mouse()
	_player.equipment.projectiles.system.set_physics_process(false)
	if _player.equipment.melee_view != null:
		_player.equipment.melee_view.set_process(false)
	_target = load("res://src/maps/testbed/target_dummy.tscn").instantiate() as TargetDummy
	_target.position = _player.position + Vector3.FORWARD
	_target.rotation.y = PI
	add_child_autofree(_target)
	_target.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _command(tick: int, attack: bool = false) -> PlayerInput:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = tick
	inp.melee = attack
	return inp


func test_short_v_press_is_buffered_once_and_echo_is_ignored() -> void:
	var reader: LocalInputReader = LocalInputReader.new()
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_V
	key.pressed = true
	reader.handle_input_event(key)
	key.pressed = false
	reader.handle_input_event(key)
	assert_true(reader.read_input().melee)
	assert_false(reader.read_input().melee)
	key.pressed = true
	key.echo = true
	reader.handle_input_event(key)
	assert_false(reader.read_input().melee)


func test_player_input_starts_knife_without_gunshot_or_grenade_or_ads() -> void:
	await _setup_player()
	var inp: PlayerInput = _command(1, true)
	inp.buttons = PlayerInput.BTN_FIRE | PlayerInput.BTN_AIM
	inp.throw_grenade = true
	var ammo: int = _player.weapon.ammo_in_mag
	_player.step_simulation(inp, 1.0 / 60.0)
	assert_true(_player.equipment.melee.busy)
	assert_true(_player.equipment.melee_view.visible)
	assert_eq(_player.weapon.ammo_in_mag, ammo)
	assert_eq(_player.ads.target, 0.0)
	assert_false(_player.equipment.projectiles.system.projectiles[0].active)
	inp = _command(13)
	_player.step_simulation(inp, 1.0 / 60.0)
	assert_eq(_target.health_component.current, 50.0)
	assert_eq((_player.health_component as HealthComponent).current, 100.0)


func test_switch_command_has_priority_and_switching_blocks_new_knife() -> void:
	await _setup_player()
	var inp: PlayerInput = _command(1, true)
	inp.weapon_slot = 2
	_player.step_simulation(inp, 1.0 / 60.0)
	assert_ne(_player.inventory.phase, Inventory.Phase.READY)
	assert_false(_player.equipment.melee.busy)


func test_busy_knife_blocks_switch_then_restores_weapon_after_finish() -> void:
	await _setup_player()
	_player.step_simulation(_command(1, true), 1.0 / 60.0)
	var inp: PlayerInput = _command(2)
	inp.weapon_slot = 2
	_player.step_simulation(inp, 1.0 / 60.0)
	assert_eq(_player.inventory.active_slot, 1)
	assert_eq(_player.inventory.phase, Inventory.Phase.READY)
	_player.equipment.simulate_melee(_command(43))
	assert_false(_player.equipment.melee.busy)
	assert_false(_player.equipment.melee_view.visible)
	assert_true(_player.ads_view.visible)
	_player.step_simulation(_command(44), 1.0 / 60.0)
	assert_eq(_player.weapon.ammo_in_mag, _player.weapon.data.mag_size)


func test_reload_blocks_melee_and_death_cancels_pending_hit() -> void:
	await _setup_player()
	_player.weapon.ammo_in_mag -= 1
	var inp: PlayerInput = _command(1)
	inp.buttons = PlayerInput.BTN_RELOAD
	_player.weapon.simulate(inp)
	assert_eq(_player.weapon.state, Weapon.State.RELOADING)
	_player.step_simulation(_command(2, true), 1.0 / 60.0)
	assert_false(_player.equipment.melee.busy)
	_player.weapon.setup(_player.weapon.data)
	_player.step_simulation(_command(3, true), 1.0 / 60.0)
	assert_true(_player.equipment.melee.busy)
	(_player.health_component as HealthComponent).apply_damage(1000.0)
	_player.step_simulation(_command(15), 1.0 / 60.0)
	assert_false(_player.equipment.melee.busy)
	assert_false(_player.equipment.melee_view.visible)
	assert_eq(_target.health_component.current, 100.0)


func test_procedural_pose_material_and_repeated_attacks_reuse_nodes() -> void:
	await _setup_player()
	var attack: MeleeAttack = _player.equipment.melee
	var view: MeleeView = _player.equipment.melee_view
	var nodes: int = get_tree().get_node_count()
	var health: float = _target.health_component.current
	for index: int in range(100):
		_player.equipment.simulate_melee(_command(1 + index * 60, true))
		assert_eq(view.position, attack.data.windup_offset)
		view.advance(attack.data.hit_delay)
		assert_almost_eq(view.position, attack.data.strike_offset, 0.001)
		view.advance(attack.data.duration)
		assert_almost_eq(view.position, attack.data.rest_offset, 0.001)
		view.advance(-1.0)
		assert_almost_eq(view.position, attack.data.rest_offset, 0.001)
		_player.equipment.simulate_melee(_command(43 + index * 60))
		assert_false(view.visible)
		assert_eq(get_tree().get_node_count(), nodes)
	assert_eq(view.get_child_count(), 2)
	assert_eq(health - _target.health_component.current, 100.0)
	var blade: MeshInstance3D = view.get_child(0) as MeshInstance3D
	var material: BaseMaterial3D = blade.mesh.surface_get_material(0) as BaseMaterial3D
	assert_true(material.no_depth_test)
	assert_true(material.use_fov_override)
	assert_eq(material.fov_override, attack.data.viewmodel_fov)


func test_cosmetic_signals_never_apply_damage() -> void:
	await _setup_player()
	var attack: MeleeAttack = _player.equipment.melee
	attack.attack_started.emit()
	_player.equipment.melee_view.advance(attack.data.hit_delay)
	assert_eq(_target.health_component.current, 100.0)
	assert_false(attack.busy)
	attack.attack_finished.emit()
	assert_eq(_target.health_component.current, 100.0)


func test_remote_and_dedicated_players_have_simulation_without_knife_view() -> void:
	await _setup_player(false)
	assert_not_null(_player.equipment.melee)
	assert_null(_player.equipment.melee_view)
	var previous: bool = Game.is_dedicated
	Game.is_dedicated = true
	var dedicated: Player = load("res://src/player/player.tscn").instantiate() as Player
	dedicated.is_local_player = true
	add_child_autofree(dedicated)
	dedicated.release_mouse()
	Game.is_dedicated = previous
	assert_not_null(dedicated.equipment.melee)
	assert_null(dedicated.equipment.melee_view)
