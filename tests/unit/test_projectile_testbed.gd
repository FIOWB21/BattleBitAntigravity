extends GutTest


func test_grenade_parabola_and_wall_bounce_on_real_testbed() -> void:
	var world: Node3D = load("res://src/maps/testbed/testbed.tscn").instantiate() as Node3D
	add_child_autofree(world)
	var player: Player = world.get_node("Player") as Player
	player.set_physics_process(false)
	player.set_process(false)
	player.release_mouse()
	var system: ProjectileSystem = player.equipment.projectiles.system
	system.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var data: ProjectileData = load("res://src/weapons/projectiles/frag.tres").duplicate() as ProjectileData
	data.drag = 0.0
	var start: Vector3 = Vector3(-20.0, 1.5, -11.0)
	var grenade: Projectile = system.launch(data, start, Vector3(0.0, 2.0, -8.0))
	for tick: int in range(15):
		grenade.simulate(1.0 / 60.0)
	assert_almost_eq(grenade.global_position, start + Vector3(0.0, 0.19375, -2.0), 0.001)
	for tick: int in range(15):
		grenade.simulate(1.0 / 60.0)
	assert_gt(grenade.velocity.z, 0.0, "Wall_3_0m reverses z velocity")
	assert_lt(grenade.velocity.y, 0.0, "Gravity pulls grenade down after apex")
	assert_gt(grenade.global_position.z, -14.75)
	for tick: int in range(150):
		grenade.simulate(1.0 / 60.0)
	assert_false(grenade.active)
	assert_eq(grenade.age, 3.0)
	assert_true(grenade.global_position.y >= 0.0)
	print("ACCEPT 2.10: real testbed parabola, Wall_3_0m bounce, floor, fuse=3s point=",
		grenade.global_position)
