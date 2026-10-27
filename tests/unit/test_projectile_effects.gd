extends GutTest

var _world: Node3D
var _system: ProjectileSystem
var _effects: ProjectileEffects
var _camera: Camera3D


func before_each() -> void:
	_world = Node3D.new()
	_world.position = Vector3(1000.0, 30.0, 1000.0)
	add_child_autofree(_world)
	_system = ProjectileSystem.new()
	_system.capacity = 2
	_world.add_child(_system)
	_system.set_physics_process(false)
	_camera = Camera3D.new()
	_world.add_child(_camera)
	_effects = ProjectileEffects.new()
	_world.add_child(_effects)
	_effects.setup(_system, _camera)
	_effects.set_process(false)


func _data(name: String) -> ProjectileData:
	return load("res://src/weapons/projectiles/%s.tres" % name) as ProjectileData


func test_smoke_grows_fades_and_reuses_fixed_visual_and_audio_nodes() -> void:
	var data: ProjectileData = _data("smoke")
	var nodes: int = get_tree().get_node_count()
	_effects.present(data, _world.global_position)
	var visual: ProjectileVisual = _effects.pool.items[0] as ProjectileVisual
	_effects.advance(2.0)
	assert_true(visual.visible)
	assert_eq(visual.mesh.scale, Vector3.ONE * data.radius)
	assert_gt(visual.material.albedo_color.a, 0.9)
	assert_false(_effects.flash.visible)
	assert_eq(_effects.sensory_remaining, 0.0)
	_effects.advance(data.effect_duration)
	assert_false(visual.visible)
	for index: int in range(100):
		_effects.present(data, _world.global_position)
	assert_eq(_effects.pool.items.size(), _effects.config.effect_capacity)
	assert_eq(_effects.pool.items[0], visual)
	assert_eq(get_tree().get_node_count(), nodes)


func test_flash_requires_facing_and_exposure_and_decays_with_ringing() -> void:
	var data: ProjectileData = _data("flash")
	_effects.present(data, _camera.global_position + Vector3.FORWARD)
	assert_true(_effects.flash.visible)
	assert_gt(_effects.flash.color.a, 0.9)
	assert_true(_effects.ringing.playing)
	_effects.advance(1.0)
	assert_lt(_effects.flash.color.a, 0.9)
	_effects.advance(10.0)
	assert_false(_effects.flash.visible)
	assert_false(_effects.ringing.playing)
	_effects.present(data, _camera.global_position + Vector3.BACK)
	assert_eq(_effects.sensory_remaining, 0.0)


func test_solid_wall_blocks_flash_and_frag_sensory_effects() -> void:
	var wall: StaticBody3D = StaticBody3D.new()
	wall.position = Vector3(0.0, 0.0, -1.0)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(5.0, 5.0, 0.1)
	collision.shape = box
	wall.add_child(collision)
	_world.add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for name: String in ["flash", "frag"]:
		_effects.present(_data(name), _camera.global_position + Vector3.FORWARD * 2.0)
	assert_false(_effects.flash.visible)
	assert_eq(_effects.sensory_remaining, 0.0)


func test_frag_stun_is_cosmetic_and_presentation_does_not_launch_or_damage() -> void:
	_effects.present(_data("frag"), _camera.global_position + Vector3.FORWARD)
	assert_true(_effects.flash.visible)
	assert_lt(_effects.flash.color.a, 0.4)
	assert_true(_effects.ringing.playing)
	assert_false(_system.projectiles[0].active)
	assert_false(_system.projectiles[1].active)
	var sound: AudioStreamWAV = _effects.ringing.stream as AudioStreamWAV
	assert_eq(sound.mix_rate, _effects.config.sample_rate)
	assert_eq(sound.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(sound.data.size(), sound.mix_rate * 2)


func test_smoke_and_projectile_stay_in_world_space_when_shooter_parent_moves() -> void:
	var point: Vector3 = _world.global_position
	_effects.present(_data("smoke"), point)
	var grenade: Projectile = _system.launch(_data("frag"), point, Vector3.ZERO)
	_world.position += Vector3(10.0, 0.0, 5.0)
	assert_eq((_effects.pool.items[0] as ProjectileVisual).global_position, point)
	assert_eq(grenade.global_position, point)


func test_frag_does_not_cancel_stronger_flash_and_senses_end_independently() -> void:
	var point: Vector3 = _camera.global_position + Vector3.FORWARD
	_effects.present(_data("flash"), point)
	var alpha: float = _effects.flash.color.a
	_effects.present(_data("frag"), point)
	assert_almost_eq(_effects.flash.color.a, alpha, 0.001)
	assert_eq(_effects.flash.color.r, 1.0)
	assert_eq(_effects.flash.color.g, 1.0)
	_effects.advance(20.0)
	assert_false(_effects.flash.visible)
	assert_false(_effects.ringing.playing)
