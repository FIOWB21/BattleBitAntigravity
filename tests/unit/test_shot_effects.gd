extends GutTest

var _world: Node3D
var _effects: ShotEffects
var _camera: Camera3D
var _weapon: Weapon


func before_each() -> void:
	_world = Node3D.new()
	_world.position = Vector3(700.0, 50.0, 700.0)
	add_child_autofree(_world)
	_camera = Camera3D.new()
	_world.add_child(_camera)
	_weapon = Weapon.new()
	_weapon.data = WeaponData.new()
	_world.add_child(_weapon)
	_effects = ShotEffects.new()
	_world.add_child(_effects)
	_effects.setup(_camera, true)
	_effects.set_process(false)


func _trace(pellet: int = 0, hit: HitResult = null) -> void:
	_effects.present_trace(_weapon, 1, pellet, _world.global_position,
		Vector3.FORWARD, hit if hit != null else HitResult.new())


func test_pellets_share_one_flash_shell_and_fire_sound_with_every_third_shot_traced() -> void:
	for shot: int in range(9):
		for pellet: int in range(8):
			_trace(pellet)
	assert_eq(_effects.shots_presented, 9)
	assert_eq(_effects.flashes.acquired_count, 9)
	assert_eq(_effects.shells.acquired_count, 9)
	assert_eq(_effects.audio.pool.acquired_count, 9)
	assert_eq(_effects.tracers.acquired_count, 24)
	assert_eq(_effects.whizzes_presented, 0)


func test_six_surfaces_select_prebuilt_geometry_and_skip_flesh_water_holes() -> void:
	var collider: StaticBody3D = StaticBody3D.new()
	_world.add_child(collider)
	var hit: HitResult = HitResult.new()
	hit.hit = true
	hit.collider = collider
	hit.point = _world.global_position + Vector3.FORWARD * 10.0
	hit.normal = Vector3.BACK
	for surface: int in range(6):
		collider.set_meta(&"surface_type", ShotSurface.NAMES[surface])
		_trace(0, hit)
		var impact: ShotVisual = _effects.impacts.items[surface] as ShotVisual
		assert_eq(impact.surface, surface)
		assert_eq(impact.mesh, _effects.assets.impacts[surface])
		assert_true(impact.visible)
	assert_eq(_effects.decals.pool.acquired_count, 4)
	assert_false(_effects.marker.visible, "A trace alone cannot confirm damage")


func test_decal_ring_replaces_oldest_of_exactly_256_and_projects_along_normal() -> void:
	var decals: ShotDecals = _effects.decals
	var point: Vector3 = _world.global_position
	var first: Decal = decals.pool.items[0] as Decal
	for index: int in range(ShotDecals.CAPACITY + 1):
		decals.stamp(point + Vector3.RIGHT * index, Vector3.BACK, ShotSurface.Type.METAL)
	assert_eq(decals.pool.get_child_count(), 256)
	assert_eq(first.global_position, point + Vector3.RIGHT * 256)
	assert_almost_eq(first.global_basis.y, Vector3.BACK, 0.00001)
	assert_eq(first.texture_albedo, _effects.assets.hole)
	assert_eq(first.size, _effects.config.decal_size)


func test_audio_has_exactly_32_reused_spatial_voices_and_custom_fire_stream() -> void:
	var first: AudioStreamPlayer3D = _effects.audio.pool.items[0] as AudioStreamPlayer3D
	_weapon.data.fire_sound = _effects.assets.whiz_sound
	for shot: int in range(ShotAudio.CAPACITY + 1):
		_trace()
	assert_eq(_effects.audio.pool.get_child_count(), 32)
	assert_eq(first.stream, _weapon.data.fire_sound)
	assert_almost_eq(first.global_position.distance_to(_world.global_position),
		_effects.config.world_muzzle_offset.length(), 0.001)
	assert_eq(first.max_distance, _effects.config.audio_distance)


func test_flash_light_survives_current_frame_and_turns_off_on_next_frame() -> void:
	var flash: MuzzleFlash = _effects.flashes.items[0] as MuzzleFlash
	flash.pulse(Transform3D.IDENTITY, 5)
	assert_true(flash.particles is GPUParticles3D)
	assert_true(flash.particles.one_shot)
	flash.advance(0.001, 5)
	assert_true(flash.light.visible)
	flash.advance(0.001, 6)
	assert_false(flash.light.visible)
	flash.advance(1.0, 7)
	assert_false(flash.visible)
	flash.pulse(Transform3D.IDENTITY, 8)
	assert_true(flash.light.visible)
	flash.advance(0.2, 8)
	assert_true(flash.visible, "Even at 5 FPS the light must be rendered once")
	assert_true(flash.light.visible)
	flash.advance(0.2, 9)
	assert_false(flash.visible)


func test_visuals_expire_reset_and_tracer_never_extends_past_impact() -> void:
	var tracer: ShotVisual = _effects.tracers.items[0] as ShotVisual
	var point: Vector3 = _world.global_position
	tracer.play_tracer(point, point + Vector3.FORWARD)
	assert_almost_eq(tracer.scale.z, 1.0, 0.001)
	assert_almost_eq(tracer.global_position.z, point.z - 0.5, 0.001)
	tracer.advance(1.0)
	assert_false(tracer.visible)
	tracer.play_tracer(point, point)
	assert_false(tracer.visible)
	_trace()
	var shell: ShotVisual = _effects.shells.items[0] as ShotVisual
	var shell_start: Vector3 = shell.global_position
	_effects.advance(0.1)
	assert_gt(shell.global_position.x, shell_start.x)
	assert_gt(shell.global_position.y, shell_start.y)
	_effects.advance(3.0)
	assert_false(shell.visible)
	shell.play_shell(Transform3D.IDENTITY)
	assert_eq(shell.transparency, 0.0)
	assert_true(shell.visible)


func test_confirmed_damage_has_timed_headshot_marker_and_sound_without_ammo_changes() -> void:
	var ammo: int = _weapon.ammo_in_mag
	var event: DamageEvent = DamageEvent.new()
	event.damage = 30.0
	event.zone = HitboxZone.HEAD
	_effects.present_damage(event)
	assert_true(_effects.marker.visible)
	assert_true(_effects.marker.headshot)
	var voice: AudioStreamPlayer3D = _effects.audio.pool.items[0] as AudioStreamPlayer3D
	assert_eq(voice.stream, _effects.assets.headshot_sound)
	assert_eq(voice.global_position, _camera.global_position)
	_effects.marker.advance(_effects.config.hit_marker_duration)
	assert_false(_effects.marker.visible)
	event.damage = 0.0
	_effects.present_damage(event)
	assert_false(_effects.marker.visible)
	assert_eq(_effects.audio.pool.acquired_count, 1)
	assert_eq(_weapon.ammo_in_mag, ammo)


func test_remote_near_miss_uses_actual_hit_endpoint_and_has_no_hit_marker() -> void:
	var remote: ShotEffects = ShotEffects.new()
	_world.add_child(remote)
	remote.setup(_camera, false)
	remote.set_process(false)
	var from: Vector3 = _camera.global_position + Vector3(1.0, 0.0, 5.0)
	var hit: HitResult = HitResult.new()
	hit.hit = true
	hit.point = from + Vector3.FORWARD * 10.0
	hit.normal = Vector3.BACK
	remote.present_trace(_weapon, 1, 0, from, Vector3.FORWARD, hit)
	assert_eq(remote.whizzes_presented, 1)
	assert_null(remote.marker)
	hit.point = from + Vector3.FORWARD
	remote.present_trace(_weapon, 2, 0, from, Vector3.FORWARD, hit)
	assert_eq(remote.whizzes_presented, 1, "A wall before the listener prevents whiz")
	assert_eq(remote.audio.pool.acquired_count, 3)


func test_invalid_delta_does_not_move_visuals() -> void:
	_trace()
	var shell: ShotVisual = _effects.shells.items[0] as ShotVisual
	var initial: Transform3D = shell.global_transform
	for delta: float in [0.0, -1.0, INF, NAN]:
		_effects.advance(delta)
		assert_eq(shell.global_transform, initial)
