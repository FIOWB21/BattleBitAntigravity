extends GutTest

const TESTBED_SCENE_PATH: String = "res://src/maps/testbed/testbed.tscn"
const WORLD_LAYER: int = 1


func _instantiate_testbed() -> Node3D:
	var packed: PackedScene = load(TESTBED_SCENE_PATH) as PackedScene
	assert_not_null(packed, "testbed.tscn must load as PackedScene")
	var inst: Node3D = packed.instantiate() as Node3D
	assert_not_null(inst, "testbed.tscn root must be Node3D")
	return inst


func test_environment_light_and_spawn() -> void:
	var root: Node3D = _instantiate_testbed()
	var spawn: Marker3D = root.get_node_or_null("PlayerSpawn") as Marker3D
	assert_not_null(spawn, "Testbed must contain Marker3D PlayerSpawn")

	var world_env: WorldEnvironment = root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	assert_not_null(world_env, "Testbed must contain WorldEnvironment")
	assert_not_null(world_env.environment, "WorldEnvironment must have an Environment resource")
	assert_eq(world_env.environment.background_mode, Environment.BG_SKY, "Environment must use sky background")

	var sun: DirectionalLight3D = root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	assert_not_null(sun, "Testbed must contain DirectionalLight3D")
	assert_true(sun.shadow_enabled, "DirectionalLight3D must have shadows enabled")
	root.free()


func test_floor_dimensions_and_grid_material() -> void:
	var root: Node3D = _instantiate_testbed()
	var floor_body: StaticBody3D = root.get_node_or_null("Floor") as StaticBody3D
	assert_not_null(floor_body, "Testbed must contain Floor StaticBody3D")
	assert_eq(floor_body.collision_layer, WORLD_LAYER, "Floor must be on physics layer world (1)")

	var col: CollisionShape3D = floor_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shape: BoxShape3D = col.shape as BoxShape3D
	assert_almost_eq(shape.size.x, 200.0, 0.001, "Floor width must be 200 m")
	assert_almost_eq(shape.size.z, 200.0, 0.001, "Floor length must be 200 m")

	var mesh_inst: MeshInstance3D = floor_body.get_node_or_null("MeshInstance3D") as MeshInstance3D
	var mat: ShaderMaterial = mesh_inst.material_override as ShaderMaterial
	assert_not_null(mat, "Floor must have ShaderMaterial for 1m grid")
	assert_almost_eq(float(mat.get_shader_parameter("grid_step")), 1.0, 0.001, "Grid step must be 1.0 m")
	root.free()


func test_floor_visual_matches_collision_and_surface_stays_at_ground_level() -> void:
	var root: Node3D = _instantiate_testbed()
	var floor_body: StaticBody3D = root.get_node("Floor") as StaticBody3D
	var col: CollisionShape3D = floor_body.get_node("CollisionShape3D") as CollisionShape3D
	var visual: MeshInstance3D = floor_body.get_node("MeshInstance3D") as MeshInstance3D
	var shape: BoxShape3D = col.shape as BoxShape3D
	var mesh: BoxMesh = visual.mesh as BoxMesh
	assert_eq(visual.transform, col.transform, "Floor mesh must match its collision transform")
	assert_eq(mesh.size, shape.size, "Floor mesh must match its collision size")
	var collision_top: Vector3 = floor_body.transform * (col.transform * Vector3(0.0, shape.size.y * 0.5, 0.0))
	var visual_top: Vector3 = floor_body.transform * (visual.transform * Vector3(0.0, mesh.size.y * 0.5, 0.0))
	assert_almost_eq(collision_top.y, 0.0, 0.001, "Floor collision surface must stay at y=0")
	assert_almost_eq(visual_top, collision_top, 0.001, "Visible floor surface must match collision")
	root.free()


func test_all_colliders_on_world_layer_and_min_10_obstacle_heights() -> void:
	var root: Node3D = _instantiate_testbed()
	var bodies: Array[StaticBody3D] = _collect_static_bodies(root)
	assert_true(bodies.size() >= 10, "Scene must contain at least 10 static bodies")
	for body: StaticBody3D in bodies:
		assert_eq(body.collision_layer, WORLD_LAYER, "%s must be on layer world (1)" % body.name)

	var obstacles_root: Node3D = root.get_node_or_null("Obstacles") as Node3D
	assert_not_null(obstacles_root, "Testbed must have Obstacles node")
	var obstacle_bodies: Array[StaticBody3D] = _collect_static_bodies(obstacles_root)
	assert_true(obstacle_bodies.size() >= 10, "Must have at least 10 obstacle bodies")

	var distinct_heights: Dictionary = {}
	for obs: StaticBody3D in obstacle_bodies:
		var col: CollisionShape3D = obs.get_node("CollisionShape3D") as CollisionShape3D
		var box: BoxShape3D = col.shape as BoxShape3D
		var top_y: float = snappedf(obs.position.y + box.size.y * 0.5, 0.01)
		distinct_heights[top_y] = true
	assert_true(distinct_heights.size() >= 10, "Must have at least 10 obstacles of different heights")
	root.free()


func test_walls_ramps_and_stairs() -> void:
	var root: Node3D = _instantiate_testbed()
	var obs: Node3D = root.get_node("Obstacles") as Node3D
	var expected_walls: Dictionary = {
		"Wall_1_0m": 1.0,
		"Wall_1_5m": 1.5,
		"Wall_2_0m": 2.0,
		"Wall_3_0m": 3.0,
	}
	for wall_name: String in expected_walls.keys():
		var wall: StaticBody3D = obs.get_node_or_null(wall_name) as StaticBody3D
		assert_not_null(wall, "Missing wall %s" % wall_name)
		var box: BoxShape3D = (wall.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
		assert_almost_eq(box.size.y, float(expected_walls[wall_name]), 0.001, "%s height mismatch" % wall_name)

	for angle: int in [15, 30, 45]:
		var ramp: StaticBody3D = obs.get_node_or_null("Ramp_%ddeg" % angle) as StaticBody3D
		assert_not_null(ramp, "Missing Ramp_%ddeg" % angle)
		assert_almost_eq(ramp.rotation_degrees.x, float(angle), 0.01, "Ramp angle must be %d deg" % angle)

	var step1: StaticBody3D = obs.get_node_or_null("StairStep_01") as StaticBody3D
	var step2: StaticBody3D = obs.get_node_or_null("StairStep_02") as StaticBody3D
	assert_not_null(step1, "Missing StairStep_01")
	assert_not_null(step2, "Missing StairStep_02")
	var h1: float = ((step1.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D).size.y
	var h2: float = ((step2.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D).size.y
	assert_almost_eq(h1, 0.2, 0.001, "First stair step height must be 0.2 m")
	assert_almost_eq(h2 - h1, 0.2, 0.001, "Stair step increment must be 0.2 m")
	root.free()


func test_corridor_tunnel_and_shooting_range() -> void:
	var root: Node3D = _instantiate_testbed()
	var obs: Node3D = root.get_node("Obstacles") as Node3D
	var left_wall: StaticBody3D = obs.get_node("Corridor_WallLeft") as StaticBody3D
	var right_wall: StaticBody3D = obs.get_node("Corridor_WallRight") as StaticBody3D
	var wall_w: float = ((left_wall.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D).size.x
	var corridor_gap: float = (right_wall.position.x - left_wall.position.x) - wall_w
	assert_almost_eq(corridor_gap, 0.8, 0.001, "Corridor inner width must be 0.8 m")

	var roof: StaticBody3D = obs.get_node("Tunnel_Roof") as StaticBody3D
	var roof_h: float = ((roof.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D).size.y
	var tunnel_clearance: float = roof.position.y - roof_h * 0.5
	assert_almost_eq(tunnel_clearance, 1.0, 0.001, "Tunnel ceiling clearance must be 1.0 m")

	var sr: Node3D = root.get_node_or_null("ShootingRange") as Node3D
	assert_not_null(sr, "Missing ShootingRange")
	for dist: int in [10, 25, 50, 100, 200]:
		var target: StaticBody3D = sr.get_node_or_null("Target_%dm" % dist) as StaticBody3D
		assert_not_null(target, "Missing Target_%dm" % dist)
		assert_almost_eq(-target.position.z, float(dist), 0.001, "Target_%dm must be at %d m" % [dist, dist])
	root.free()


func test_testbed_in_tree_and_physics_server_layer() -> void:
	var root: Node3D = _instantiate_testbed()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(root)
	assert_eq(root.get_parent(), tree.root, "Testbed must attach to SceneTree.root cleanly")

	var floor_body: StaticBody3D = root.get_node("Floor") as StaticBody3D
	var rid: RID = floor_body.get_rid()
	assert_true(rid.is_valid(), "Floor StaticBody3D must have valid PhysicsServer3D RID")
	assert_eq(
		PhysicsServer3D.body_get_collision_layer(rid),
		WORLD_LAYER,
		"PhysicsServer3D must register Floor on layer world (1)"
	)

	tree.root.remove_child(root)
	root.free()


func _collect_static_bodies(node: Node) -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	for child: Node in node.get_children():
		if child is StaticBody3D:
			out.append(child as StaticBody3D)
		out.append_array(_collect_static_bodies(child))
	return out
