extends GutTest

var _lag: LagCompensator
var _target: Player
var _shooter: Player
var _base: Vector3 = Vector3(500.0, 20.0, 500.0)


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_lag = LagCompensator.new()
	add_child_autofree(_lag)
	_lag.set_physics_process(false)
	_target = _actor(42)
	_shooter = _actor(7)
	_shooter.position.z += 10.0
	_lag.track(_target)
	_lag.track(_shooter)


func _actor(owner_id: int) -> Player:
	var actor: Player = preload("res://src/player/player.tscn").instantiate() as Player
	actor.network_owner_id = owner_id
	actor.position = _base
	add_child_autofree(actor)
	actor.set_physics_process(false)
	return actor


func _ray(height: float = 1.0) -> HitResult:
	return HitscanQuery.cast(_base + Vector3(0.0, height, 5.0),
		_base + Vector3(0.0, height, -5.0), _shooter.get_hitscan_exclude_rids())


func test_running_target_hit_and_restore_are_visible_to_jolt_in_same_frame() -> void:
	_lag.record(90)
	_target.position.x += 3.0
	_target.velocity = Vector3(5.0, 0.0, 0.0)
	_target.hitboxes.torso_zone.force_update_transform()
	var before: Transform3D = _target.global_transform
	assert_false(_ray().hit)
	assert_true(_lag.rewind(100, 90, 7))
	assert_eq(_ray().entity, _target)
	assert_eq(_target.global_transform, before)
	_lag.restore()
	assert_false(_ray().hit)
	assert_eq(_target.global_transform, before)
	assert_eq(_target.velocity, Vector3(5.0, 0.0, 0.0))
	assert_false(_lag.active)


func test_forged_past_tick_clamps_to_250ms_and_future_to_present() -> void:
	for tick: int in range(40, 101):
		_target.position.x = _base.x + (0.0 if tick < 85 else 3.0)
		_lag.record(tick)
	assert_eq(_lag.bounded_tick(100, -9223372036854775807), 85)
	assert_eq(_lag.bounded_tick(100, 9223372036854775807), 100)
	assert_true(_lag.rewind(100, 40, 7))
	assert_eq(_lag.last_rewind_tick, 85)
	assert_false(_ray().hit, "Cannot reach the old target beyond 250 ms")
	_lag.restore()
	assert_true(_lag.rewind(100, 99999, 7))
	assert_eq(_lag.last_rewind_tick, 100)
	_lag.restore()
	assert_eq(_lag.bounded_tick(5, -100), 0)


func test_historical_orientation_stance_lean_and_shapes_restore_exactly() -> void:
	_target.stance = PlayerStance.PRONE
	_target.rotation.y = PI * 0.5
	_target.hitboxes.update_for_dimensions(0.5, 0.35, 0.25)
	_lag.record(90)
	var pose: LagPose = _lag.tracks[0].frames[90 % LagCompensator.HISTORY]
	assert_eq(pose.stance, PlayerStance.PRONE)
	assert_eq(pose.body, _target.global_transform)
	_target.stance = PlayerStance.STAND
	_target.rotation.y = 0.0
	var zone: HitboxZone = _target.hitboxes.head_zone
	zone.force_update_transform()
	var transform: Transform3D = PhysicsServer3D.area_get_transform(zone.get_rid())
	var shape: RID = PhysicsServer3D.area_get_shape(zone.get_rid(), 0)
	assert_true(_ray(1.65).hit)
	_lag.rewind(100, 90, 7)
	assert_false(_ray(1.65).hit, "Prone history has no standing head")
	assert_eq(PhysicsServer3D.area_get_transform(zone.get_rid()), pose.transforms[0])
	assert_eq(PhysicsServer3D.area_get_shape(zone.get_rid(), 0), pose.shapes[0].get_rid())
	_lag.restore()
	assert_eq(PhysicsServer3D.area_get_transform(zone.get_rid()), transform)
	assert_eq(PhysicsServer3D.area_get_shape(zone.get_rid(), 0), shape)
	assert_true(_ray(1.65).hit)
	assert_eq(_target.stance, PlayerStance.STAND)


func test_shooter_and_missing_or_overwritten_history_are_never_rewound() -> void:
	_lag.record(30)
	var oldest: LagPose = _lag.tracks[0].frames[30]
	_target.position.x += 3.0
	_shooter.position.x += 2.0
	_shooter.hitboxes.head_zone.force_update_transform()
	var pose: Transform3D = _shooter.hitboxes.head_zone.global_transform
	_lag.record(90)
	assert_eq(_lag.tracks[0].frames[30], oldest)
	assert_eq(oldest.tick, 90)
	_lag.rewind(100, 89, 7)
	assert_false(_ray().hit)
	assert_eq(PhysicsServer3D.area_get_transform(_shooter.hitboxes.head_zone.get_rid()), pose)
	assert_false(_lag.rewind(100, 90, 7), "Nested rewind cannot replace saved transforms")
	_lag.restore()
	assert_eq(_lag.tracks[0].frames.size(), 60)


func test_repeated_record_does_not_overwrite_tick_and_untrack_resets_history() -> void:
	_lag.record(90)
	_target.position.x += 3.0
	_lag.record(90)
	_lag.record(89)
	_lag.rewind(100, 90, 7)
	assert_eq(_ray().entity, _target)
	_lag.untrack(_target)
	assert_false(_ray().hit)
	assert_eq(_lag.tracks.size(), 1)
	_lag.track(_target)
	_lag.restore()
	_lag.rewind(100, 90, 7)
	assert_false(_ray().hit, "Reused peer id cannot inherit an earlier player history")
	_lag.clear()
	assert_false(_lag.active)
	assert_true(_lag.tracks.is_empty())
	assert_eq(_lag.last_rewind_tick, -1)


func test_wall_still_blocks_historical_target_and_pool_does_not_grow() -> void:
	_lag.record(90)
	_target.position.x += 3.0
	var wall: StaticBody3D = StaticBody3D.new()
	wall.position = _base + Vector3(0.0, 1.0, 2.0)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(5.0, 4.0, 0.5)
	collision.shape = shape
	wall.add_child(collision)
	add_child_autofree(wall)
	await get_tree().physics_frame
	await get_tree().process_frame
	var first: LagPose = _lag.tracks[0].frames[0]
	for tick: int in range(100, 300):
		_lag.rewind(100, 90, 7)
		assert_eq(_ray().collider, wall)
		_lag.restore()
		_lag.record(tick)
	assert_eq(_lag.tracks[0].frames.size(), 60)
	assert_eq(_lag.tracks[0].frames[0], first)
