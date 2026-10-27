extends GutTest

var _player: Player


func _setup_player() -> void:
	_player = load("res://src/player/player.tscn").instantiate() as Player
	_player.position = Vector3(800.0, 20.0, 800.0)
	add_child_autofree(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	_player.release_mouse()
	_player.equipment.projectiles.system.set_physics_process(false)


func test_short_grenade_press_is_buffered_once_and_echo_is_ignored() -> void:
	var reader: LocalInputReader = LocalInputReader.new()
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_G
	key.pressed = true
	reader.handle_input_event(key)
	key.pressed = false
	reader.handle_input_event(key)
	assert_true(reader.read_input().throw_grenade)
	assert_false(reader.read_input().throw_grenade)
	key.pressed = true
	key.echo = true
	reader.handle_input_event(key)
	assert_false(reader.read_input().throw_grenade)


func test_player_input_launches_from_simulation_pose_and_throttles_repeat_ticks() -> void:
	_setup_player()
	var component: PlayerProjectiles = _player.equipment.projectiles
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.yaw = PI * 0.5
	inp.throw_grenade = true
	_player.step_simulation(inp, 1.0 / 60.0)
	var grenade: Projectile = component.system.projectiles[0]
	assert_true(grenade.active)
	assert_almost_eq(grenade.global_position, _player.head.global_position, 0.001)
	assert_almost_eq(grenade.velocity, Vector3(-16.0, 3.0, 0.0), 0.001)
	assert_eq(grenade.attacker, _player.get_multiplayer_authority())
	component.simulate(inp)
	inp.tick = 2
	component.simulate(inp)
	assert_false(component.system.projectiles[1].active)
	inp.tick = 1 + ceili(component.profile.throw_interval * Engine.physics_ticks_per_second)
	component.simulate(inp)
	assert_true(component.system.projectiles[1].active)


func test_dead_player_cannot_throw_but_previous_grenade_keeps_simulating() -> void:
	_setup_player()
	var component: PlayerProjectiles = _player.equipment.projectiles
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.throw_grenade = true
	component.simulate(inp)
	(_player.health_component as HealthComponent).apply_damage(1000.0)
	inp.tick = 1000
	component.simulate(inp)
	assert_false(component.system.projectiles[1].active)
	component.system.advance(3.0)
	assert_false(component.system.projectiles[0].active)


func test_dedicated_player_retains_simulation_and_has_no_projectile_cosmetics() -> void:
	var previous: bool = Game.is_dedicated
	Game.is_dedicated = true
	_setup_player()
	Game.is_dedicated = previous
	assert_not_null(_player.equipment.projectiles.system)
	assert_null(_player.equipment.projectiles.effects)
