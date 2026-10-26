extends GutTest

const PLAYER_SCENE_PATH: String = "res://src/player/player.tscn"
const UPDATE_COUNT: int = 120


func before_each() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame


func _shapes_of(hitboxes: PlayerHitboxes) -> Array[Shape3D]:
	var shapes: Array[Shape3D] = []
	for zone: HitboxZone in hitboxes.get_zones():
		var collision: CollisionShape3D = zone.get_node("CollisionShape3D") as CollisionShape3D
		shapes.append(collision.shape)
	return shapes


func _assert_same_shapes(hitboxes: PlayerHitboxes, expected: Array[Shape3D]) -> void:
	var actual: Array[Shape3D] = _shapes_of(hitboxes)
	assert_eq(actual.size(), expected.size())
	assert_eq(hitboxes.get_child_count(), 5, "Updates must not create extra zones")
	for i: int in range(expected.size()):
		assert_eq(actual[i], expected[i], "Shape resources must survive updates")
		assert_eq(actual[i].get_rid(), expected[i].get_rid(), "Physics shapes must be reused")
		assert_eq(hitboxes.get_zones()[i].get_child_count(), 1)


func test_generated_shapes_survive_ready_updates_and_repeated_setup() -> void:
	var health: HealthComponent = HealthComponent.new()
	add_child_autofree(health)
	var movement: MovementConfig = MovementConfig.new()
	var hitboxes: PlayerHitboxes = PlayerHitboxes.new()
	hitboxes.setup(null, health, movement)
	var shapes: Array[Shape3D] = _shapes_of(hitboxes)
	add_child_autofree(hitboxes)
	_assert_same_shapes(hitboxes, shapes)
	for tick: int in range(UPDATE_COUNT):
		hitboxes.update_for_stance(tick % 3, movement.lean_offset)
		_assert_same_shapes(hitboxes, shapes)
	var custom: HitboxConfig = HitboxConfig.new()
	custom.head_mult = 3.0
	custom.head_radius = 0.12
	var new_health: HealthComponent = HealthComponent.new()
	add_child_autofree(new_health)
	hitboxes.setup(null, new_health, movement, custom)
	_assert_same_shapes(hitboxes, shapes)
	assert_almost_eq((shapes[0] as SphereShape3D).radius, custom.head_radius, 0.0001)
	assert_almost_eq(hitboxes.head_zone.damage_mult, custom.head_mult, 0.0001)
	for zone: HitboxZone in hitboxes.get_zones():
		assert_eq(zone.health_component, new_health, "Repeated setup must rebind health")
	assert_eq(hitboxes.get_exclude_rids().size(), 5)


func test_scene_shapes_are_private_and_survive_updates_and_tree_reentry() -> void:
	var scene: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	var first: Player = scene.instantiate() as Player
	var second: Player = scene.instantiate() as Player
	first.is_local_player = false
	second.is_local_player = false
	add_child_autofree(first)
	add_child_autofree(second)
	var first_shapes: Array[Shape3D] = _shapes_of(first.hitboxes)
	var second_shapes: Array[Shape3D] = _shapes_of(second.hitboxes)
	var second_head_radius: float = (second_shapes[0] as SphereShape3D).radius
	var second_torso_size: Vector3 = (second_shapes[1] as BoxShape3D).size
	var second_head_position: Vector3 = second.hitboxes.head_zone.position
	for i: int in range(first_shapes.size()):
		assert_ne(first_shapes[i], second_shapes[i], "Players must own separate shapes")
	first.hitboxes.update_for_stance(PlayerStance.PRONE, 0.4)
	_assert_same_shapes(first.hitboxes, first_shapes)
	assert_almost_eq((second_shapes[0] as SphereShape3D).radius, second_head_radius, 0.0001)
	assert_eq((second_shapes[1] as BoxShape3D).size, second_torso_size)
	assert_eq(second.hitboxes.head_zone.position, second_head_position)
	assert_lt((first_shapes[0] as SphereShape3D).radius, second_head_radius)
	first.hitboxes.request_ready()
	remove_child(first)
	add_child(first)
	_assert_same_shapes(first.hitboxes, first_shapes)
	_assert_same_shapes(second.hitboxes, second_shapes)
	assert_eq(first.get_hitscan_exclude_rids().size(), 6)
