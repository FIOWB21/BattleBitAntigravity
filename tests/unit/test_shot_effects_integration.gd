extends GutTest

var _world: Node3D
var _weapon: Weapon
var _hitscan: WeaponHitscan
var _effects: ShotEffects
var _camera: Camera3D
var _input: PlayerInput


func before_each() -> void:
	_world = Node3D.new()
	_world.position = Vector3(900.0, 20.0, 900.0)
	add_child_autofree(_world)
	_weapon = Weapon.new()
	_weapon.data = WeaponData.new()
	_weapon.data.rpm = 600.0
	_weapon.data.mag_size = 10000
	_weapon.data.spread_hip_deg = 0.0
	_weapon.data.recoil_fallback_deg = Vector2.ZERO
	_weapon.data.recoil_noise_deg = Vector2.ZERO
	_world.add_child(_weapon)
	_hitscan = WeaponHitscan.new()
	_world.add_child(_hitscan)
	_hitscan.setup(_weapon, 1, [])
	_camera = Camera3D.new()
	_world.add_child(_camera)
	_effects = ShotEffects.new()
	_world.add_child(_effects)
	_effects.setup(_camera, true)
	_effects.set_process(false)
	_effects.bind_weapon(_weapon, _hitscan)
	_input = PlayerInput.new()
	_input.buttons = PlayerInput.BTN_FIRE


func test_thirty_seconds_of_automatic_fire_keeps_node_count_and_pool_identities() -> void:
	var nodes: int = get_tree().get_node_count()
	var first_shell: Node = _effects.shells.items[0]
	var first_flash: Node = _effects.flashes.items[0]
	var first_decal: Node = _effects.decals.pool.items[0]
	var pose: Transform3D = Transform3D(Basis.IDENTITY, _world.global_position)
	for tick: int in range(1800):
		_input.tick = tick
		_hitscan.simulate(_input, pose)
		_effects.advance(1.0 / 60.0)
		assert_eq(get_tree().get_node_count(), nodes)
	assert_eq(_effects.shots_presented, 300)
	assert_eq(_weapon.ammo_in_mag, 9700)
	assert_eq(_effects.shells.items[0], first_shell)
	assert_eq(_effects.flashes.items[0], first_flash)
	assert_eq(_effects.decals.pool.items[0], first_decal)
	assert_eq(_effects.tracers.acquired_count, 100)


func test_repeated_binding_does_not_duplicate_shot_and_blocked_fire_has_no_effect() -> void:
	_effects.bind_weapon(_weapon, _hitscan)
	_effects.bind_weapon(_weapon, _hitscan)
	var pose: Transform3D = Transform3D(Basis.IDENTITY, _world.global_position)
	_input.tick = 0
	_hitscan.simulate(_input, pose, true)
	assert_eq(_effects.shots_presented, 0)
	_input.tick = 1
	_hitscan.simulate(_input, pose)
	assert_eq(_effects.shots_presented, 1)
	assert_eq(_effects.shells.acquired_count, 1)
	assert_eq(_effects.audio.pool.acquired_count, 1)
	assert_eq(_hitscan.shot_origin, _world.global_position)


func test_effects_cannot_change_trace_damage_ammo_or_handling() -> void:
	var target: TargetDummy = (load("res://src/maps/testbed/target_dummy.tscn") as PackedScene).instantiate() as TargetDummy
	target.position = Vector3(0.0, 0.0, -10.0)
	_world.add_child(target)
	target.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var pose: Transform3D = Transform3D(Basis.IDENTITY, _world.global_position + Vector3.UP * 1.125)
	_hitscan.simulate(_input, pose)
	assert_almost_eq(target.health_component.current, 70.0, 0.001)
	assert_eq(_weapon.ammo_in_mag, 9999)
	assert_true(_effects.marker.visible)
	assert_eq(_effects.decals.pool.acquired_count, 0, "Flesh cannot leave a floating bullet hole")
	var recoil: Vector2 = _hitscan.handling.recoil_deg
	var hit: HitResult = HitResult.new()
	hit.hit = true
	hit.point = target.global_position
	hit.normal = Vector3.BACK
	hit.health_component = target.health_component
	for index: int in range(100):
		_effects.present_trace(_weapon, index, 0, pose.origin, Vector3.FORWARD, hit)
		_effects.advance(0.01)
	assert_almost_eq(target.health_component.current, 70.0, 0.001)
	assert_eq(_weapon.ammo_in_mag, 9999)
	assert_eq(_hitscan.handling.recoil_deg, recoil)


func test_player_weapon_switch_uses_same_pools_and_new_active_weapon_signal() -> void:
	var player: Player = (load("res://src/player/player.tscn") as PackedScene).instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.release_mouse()
	var effects: ShotEffects = player.equipment.effects
	assert_not_null(effects)
	var voice: Node = effects.audio.pool.items[0]
	var nodes: int = get_tree().get_node_count()
	_input.tick = 0
	_input.buttons = 0
	_input.weapon_slot = 2
	player.inventory.simulate(_input)
	_input.weapon_slot = 0
	for tick: int in range(1, 91):
		_input.tick = tick
		_input.buttons = 0
		player.inventory.simulate(_input)
	assert_eq(player.weapon, player.inventory.weapon_at(2))
	_input.tick = 91
	_input.buttons = PlayerInput.BTN_FIRE
	player.weapon_hitscan.simulate(_input, Transform3D.IDENTITY)
	assert_eq(effects.shots_presented, 1)
	assert_eq(effects.audio.pool.items[0], voice)
	assert_eq(get_tree().get_node_count(), nodes)


func test_dedicated_player_has_no_cosmetic_pools() -> void:
	var previous: bool = Game.is_dedicated
	Game.is_dedicated = true
	var player: Player = (load("res://src/player/player.tscn") as PackedScene).instantiate() as Player
	add_child_autofree(player)
	Game.is_dedicated = previous
	player.set_physics_process(false)
	player.set_process(false)
	player.release_mouse()
	assert_null(player.equipment.effects)


func test_procedural_assets_are_shared_and_audio_pcm_has_expected_duration() -> void:
	var config: ShotFxConfig = _effects.config
	assert_eq(_effects.assets.impacts.size(), 6)
	var image: Image = _effects.assets.hole.get_image()
	assert_eq(image.get_width(), config.decal_texture_size)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_gt(image.get_pixel(config.decal_texture_size / 2, config.decal_texture_size / 2).a, 0.9)
	for stream: AudioStreamWAV in [_effects.assets.fire_sound, _effects.assets.hit_sound,
			_effects.assets.headshot_sound, _effects.assets.whiz_sound]:
		assert_eq(stream.mix_rate, config.sample_rate)
		assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS)
		assert_gt(stream.data.size(), 0)
		assert_eq(stream.data.size() % 2, 0)
	assert_almost_eq(_effects.assets.fire_sound.get_length(), config.fire_duration, 0.0001)
	assert_ne(_effects.assets.hit_sound.data, _effects.assets.headshot_sound.data)
