extends GutTest

const EPSILON: float = 0.00001


func test_frag_damage_center_half_edge_outside_and_occlusion() -> void:
	var data: ProjectileData = load("res://src/weapons/projectiles/frag.tres") as ProjectileData
	assert_eq(data.fuse, 3.0)
	assert_eq(data.damage_at(0.0), 150.0)
	assert_eq(data.damage_at(4.0), 75.0)
	assert_eq(data.damage_at(8.0), 0.0)
	assert_eq(data.damage_at(100.0), 0.0)
	assert_eq(data.damage_at(0.0, false), 0.0)
	assert_eq(data.damage_at(INF), 0.0)
	assert_eq(data.damage_at(NAN), 0.0)
	print("ACCEPT 2.10: explosion center=150 half=75 edge=0 occluded=0")


func test_parabola_matches_exact_gravity_and_is_partition_invariant() -> void:
	var data: ProjectileData = ProjectileData.new()
	data.drag = 0.0
	var initial: Vector3 = Vector3(10.0, 5.0, 0.0)
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = initial
	for tick: int in range(60):
		position += ProjectileBallistics.displacement(velocity, data, 1.0 / 60.0)
		velocity = ProjectileBallistics.velocity_after(velocity, data, 1.0 / 60.0)
	assert_almost_eq(position, Vector3(10.0, 0.1, 0.0), EPSILON)
	assert_almost_eq(velocity, Vector3(10.0, -4.8, 0.0), EPSILON)
	assert_almost_eq(position, ProjectileBallistics.displacement(initial, data, 1.0), EPSILON)


func test_linear_drag_is_repeatable_partition_invariant_and_reduces_speed() -> void:
	var data: ProjectileData = ProjectileData.new()
	var initial: Vector3 = Vector3(30.0, 8.0, -10.0)
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = initial
	for tick: int in range(120):
		position += ProjectileBallistics.displacement(velocity, data, 1.0 / 60.0)
		velocity = ProjectileBallistics.velocity_after(velocity, data, 1.0 / 60.0)
	assert_almost_eq(position, ProjectileBallistics.displacement(initial, data, 2.0), 0.001)
	assert_almost_eq(velocity, ProjectileBallistics.velocity_after(initial, data, 2.0), 0.001)
	assert_lt(velocity.x, initial.x)
	assert_eq(ProjectileBallistics.displacement(initial, data, 2.0),
		ProjectileBallistics.displacement(initial, data, 2.0))


func test_bounce_restitution_and_tangent_friction_never_add_energy() -> void:
	var data: ProjectileData = ProjectileData.new()
	var initial: Vector3 = Vector3(10.0, 2.0, -3.0)
	var bounced: Vector3 = ProjectileBallistics.bounced(initial, Vector3.LEFT, data)
	assert_almost_eq(bounced, Vector3(-5.0, 1.6, -2.4), EPSILON)
	assert_lt(bounced.length(), initial.length())
	assert_eq(ProjectileBallistics.bounced(initial, Vector3.RIGHT, data), initial)


func test_all_profiles_share_projectile_data_and_nonlethal_types_have_zero_damage() -> void:
	for name: String in ["frag", "smoke", "flash", "rocket"]:
		var data: ProjectileData = load("res://src/weapons/projectiles/%s.tres" % name) as ProjectileData
		assert_not_null(data)
		assert_gt(data.fuse, 0.0)
		assert_gt(data.radius, 0.0)
		if name == "smoke" or name == "flash":
			assert_eq(data.damage_at(0.0), 0.0)
		if name == "rocket":
			assert_true(data.impact_detonation)
			assert_gt(data.speed, 16.0)
