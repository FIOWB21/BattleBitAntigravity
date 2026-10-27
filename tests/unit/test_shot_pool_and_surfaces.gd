extends GutTest


func test_fixed_pool_wraps_without_creating_nodes_and_prewarm_is_idempotent() -> void:
	var pool: ObjectPool = ObjectPool.new()
	add_child_autofree(pool)
	assert_null(pool.acquire())
	pool.prewarm(3, func() -> Node: return Node.new())
	var first: Node = pool.acquire()
	var second: Node = pool.acquire()
	var third: Node = pool.acquire()
	assert_ne(first, second)
	assert_ne(second, third)
	pool.prewarm(100, func() -> Node: return Node.new())
	for index: int in range(300):
		var expected: Node = pool.items[index % 3]
		assert_eq(pool.acquire(), expected)
	assert_eq(pool.get_child_count(), 3)
	assert_eq(pool.acquired_count, 303)


func test_all_surface_metadata_unknown_values_aliases_and_flesh_priority() -> void:
	var collider: StaticBody3D = StaticBody3D.new()
	add_child_autofree(collider)
	var hit: HitResult = HitResult.new()
	hit.collider = collider
	for index: int in range(ShotSurface.NAMES.size()):
		collider.set_meta(&"surface_type", ShotSurface.NAMES[index])
		assert_eq(ShotSurface.resolve(hit), index)
		assert_eq(ShotSurface.accepts_decal(index as ShotSurface.Type), index < 4)
	for name: String in ["earth", "dirt", "ground"]:
		collider.set_meta(&"surface_type", name)
		assert_eq(ShotSurface.resolve(hit), ShotSurface.Type.EARTH)
	collider.set_meta(&"surface_type", "METAL")
	assert_eq(ShotSurface.resolve(hit), ShotSurface.Type.METAL)
	collider.set_meta(&"surface_type", "unknown")
	assert_eq(ShotSurface.resolve(hit), ShotSurface.Type.CONCRETE)
	collider.remove_meta(&"surface_type")
	assert_eq(ShotSurface.resolve(hit), ShotSurface.Type.CONCRETE)
	hit.health_component = autofree(HealthComponent.new()) as HealthComponent
	assert_eq(ShotSurface.resolve(hit), ShotSurface.Type.FLESH)
	hit.health_component = null
	hit.collider = null
	assert_eq(ShotSurface.resolve(hit), ShotSurface.Type.CONCRETE)


func test_surface_basis_handles_walls_floor_ceiling_and_degenerate_normal() -> void:
	for normal: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT,
			Vector3.FORWARD, Vector3.BACK, Vector3(1.0, 2.0, 3.0), Vector3.ZERO]:
		var orientation: Basis = ShotSurface.normal_basis(normal)
		var expected: Vector3 = normal.normalized() if normal != Vector3.ZERO else Vector3.UP
		assert_almost_eq(orientation.y, expected, 0.00001)
		assert_almost_eq(orientation.determinant(), 1.0, 0.00001)
		assert_almost_eq(orientation.x.dot(orientation.y), 0.0, 0.00001)


func test_whiz_is_limited_to_actual_segment_and_radius() -> void:
	var config: ShotFxConfig = ShotFxConfig.new()
	var from: Vector3 = Vector3(0.0, 0.0, 5.0)
	var end: Vector3 = Vector3(0.0, 0.0, -5.0)
	assert_eq(ShotAudio.whiz_point(from, end, Vector3.RIGHT, config), Vector3.ZERO)
	assert_eq(ShotAudio.whiz_point(from, end, Vector3(2.0, 0.0, 0.0), config), Vector3.ZERO)
	for ear: Vector3 in [Vector3.ZERO, Vector3(3.0, 0.0, 0.0),
			Vector3(1.0, 0.0, 6.0), Vector3(1.0, 0.0, -6.0), Vector3(1.0, 0.0, -5.0)]:
		assert_eq(ShotAudio.whiz_point(from, end, ear, config), Vector3.INF)
	assert_eq(ShotAudio.whiz_point(from, from, Vector3.RIGHT, config), Vector3.INF)
