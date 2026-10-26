extends GutTest

const EPSILON: float = 0.0001
const CONFIG: ViewmodelConfig = preload("res://src/weapons/data/default_viewmodel.tres")


func test_analytic_spring_matches_subdivided_time_and_large_frames() -> void:
	for fps: int in [5, 15, 30, 60, 144, 360]:
		var spring: ViewmodelSpring = ViewmodelSpring.new()
		spring.velocity = Vector3(1.0, -2.0, 3.0)
		var single: ViewmodelSpring = ViewmodelSpring.new()
		single.velocity = spring.velocity
		var target: Vector3 = Vector3(0.2, -0.1, 0.3)
		single.advance(target, 2.0, 1.0)
		for frame: int in range(fps):
			spring.advance(target, 2.0, 1.0 / fps)
		assert_almost_eq(spring.value, single.value, EPSILON)
		assert_almost_eq(spring.velocity, single.velocity, EPSILON)
		spring.advance(target, 5.0, 10.0)
		assert_almost_eq(spring.value, target, EPSILON)
		assert_true(spring.velocity.is_finite())
	print("ACCEPT 2.8: analytic springs stable at 5..360 FPS and 10-second frame")


func test_invalid_delta_is_ignored_and_reset_clears_impulses() -> void:
	var spring: ViewmodelSpring = ViewmodelSpring.new()
	spring.velocity = Vector3.ONE
	for delta: float in [0.0, -1.0, INF, NAN]:
		spring.advance(Vector3.ONE, 5.0, delta)
		assert_eq(spring.value, Vector3.ZERO)
		assert_eq(spring.velocity, Vector3.ONE)
	spring.reset()
	assert_eq(spring.velocity, Vector3.ZERO)


func test_zero_frequency_is_free_motion() -> void:
	var spring: ViewmodelSpring = ViewmodelSpring.new()
	spring.velocity = Vector3(0.1, 0.0, 0.0)
	spring.advance(Vector3.ONE, 0.0, 2.0)
	assert_almost_eq(spring.value, Vector3(0.2, 0.0, 0.0), EPSILON)


func test_kick_impulse_returns_to_rest_at_low_and_high_fps() -> void:
	for fps: int in [5, 15, 60, 144, 360]:
		var motion: ViewmodelMotion = ViewmodelMotion.new()
		motion.kick(CONFIG)
		assert_eq(motion.offset.velocity, CONFIG.kick_velocity)
		for frame: int in range(fps * 2):
			motion.advance(CONFIG, 1.0 / fps, 0.0, true, false)
			assert_true(motion.offset.value.is_finite())
			assert_lt(motion.offset.value.length(), 1.0)
		assert_almost_eq(motion.offset.value, Vector3.ZERO, EPSILON)
		assert_almost_eq(motion.angles.value, Vector3.ZERO, EPSILON)


func test_mouse_sway_is_bounded_and_does_not_depend_on_event_count() -> void:
	var batched: ViewmodelMotion = ViewmodelMotion.new()
	var split: ViewmodelMotion = ViewmodelMotion.new()
	batched.add_look_delta(Vector2(0.2, -0.1))
	for event: int in range(10):
		split.add_look_delta(Vector2(0.02, -0.01))
	batched.advance(CONFIG, 0.1, 0.0, true, false)
	split.advance(CONFIG, 0.1, 0.0, true, false)
	assert_almost_eq(batched.angles.value, split.angles.value, EPSILON)
	assert_gt(absf(batched.angles.value.y), 0.0)
	assert_lte(batched.angles.value.length(), CONFIG.sway_max_radians * sqrt(2.0))
	batched.advance(CONFIG, 2.0, 0.0, true, false)
	assert_almost_eq(batched.angles.value, Vector3.ZERO, EPSILON)


func test_continuous_mouse_motion_has_same_response_at_different_fps() -> void:
	var reference: Vector3 = Vector3.ZERO
	for fps: int in [15, 60, 144, 360]:
		var motion: ViewmodelMotion = ViewmodelMotion.new()
		for frame: int in range(fps):
			motion.add_look_delta(Vector2(0.5, -0.3) / fps)
			motion.advance(CONFIG, 1.0 / fps, 0.0, true, false)
		if reference == Vector3.ZERO:
			reference = motion.angles.value
		assert_almost_eq(motion.angles.value, reference, EPSILON)


func test_bob_requires_grounded_movement_and_remains_bounded() -> void:
	var motion: ViewmodelMotion = ViewmodelMotion.new()
	motion.advance(CONFIG, 0.1, 5.0, false, false)
	assert_eq(motion.offset.value, Vector3.ZERO)
	motion.advance(CONFIG, 0.1, 0.0, true, false)
	assert_eq(motion.offset.value, Vector3.ZERO)
	motion.advance(CONFIG, 0.1, 5.0, true, false)
	assert_gt(motion.offset.value.length(), 0.0)
	for frame: int in range(120):
		motion.advance(CONFIG, 0.1, 100.0, true, false)
		assert_lt(motion.offset.value.length(), CONFIG.bob_offset.length())
	motion.advance(CONFIG, 2.0, 0.0, false, false)
	assert_almost_eq(motion.offset.value, Vector3.ZERO, EPSILON)


func test_sprint_pose_converges_and_returns_without_bob() -> void:
	var motion: ViewmodelMotion = ViewmodelMotion.new()
	motion.advance(CONFIG, 1.0, 0.0, true, true)
	assert_almost_eq(motion.offset.value, CONFIG.sprint_offset, EPSILON)
	assert_almost_eq(motion.angles.value, CONFIG.sprint_rotation, EPSILON)
	motion.advance(CONFIG, 1.0, 0.0, true, false)
	assert_almost_eq(motion.offset.value, Vector3.ZERO, EPSILON)
	assert_almost_eq(motion.angles.value, Vector3.ZERO, EPSILON)


func test_reload_curve_duration_cancel_and_zero_duration() -> void:
	assert_eq(CONFIG.reload_curve.sample(0.0), 0.0)
	assert_eq(CONFIG.reload_curve.sample(1.0), 0.0)
	var motion: ViewmodelMotion = ViewmodelMotion.new()
	motion.start_reload(2.0)
	motion.advance(CONFIG, 0.5, 0.0, true, false)
	assert_true(motion.reloading)
	assert_almost_eq(motion.offset.value, CONFIG.reload_offset, EPSILON)
	motion.stop_reload()
	motion.advance(CONFIG, 1.0, 0.0, true, false)
	assert_almost_eq(motion.offset.value, Vector3.ZERO, EPSILON)
	motion.start_reload(0.0)
	assert_false(motion.reloading)
	motion.start_reload(2.0)
	motion.advance(CONFIG, 2.0, 0.0, true, false)
	assert_false(motion.reloading)
	assert_eq(motion.reload_elapsed, 2.0)


func test_reset_clears_all_motion_state() -> void:
	var motion: ViewmodelMotion = ViewmodelMotion.new()
	motion.start_reload(2.0)
	motion.kick(CONFIG)
	motion.add_look_delta(Vector2.ONE)
	motion.reset()
	motion.advance(CONFIG, 0.1, 0.0, true, false)
	assert_eq(motion.offset.value, Vector3.ZERO)
	assert_eq(motion.angles.value, Vector3.ZERO)
	assert_false(motion.reloading)
