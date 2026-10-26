extends SceneTree

const OUTPUT_PATH: String = "res://src/maps/testbed/testbed.tscn"
const GRID_SHADER_PATH: String = "res://src/maps/testbed/grid_1m.gdshader"
const PLAYER_SCENE_PATH: String = "res://src/player/player.tscn"
const TARGET_DUMMY_SCENE_PATH: String = "res://src/maps/testbed/target_dummy.tscn"
const HUD_SCENE_PATH: String = "res://src/ui/hud/hud.tscn"
const DEBUG_OVERLAY_SCENE_PATH: String = "res://src/ui/debug_overlay.tscn"
const WORLD_LAYER: int = 1
const AMMO_BOX_PATH: String = "res://src/maps/testbed/ammo_box.tscn"
const AMMO_BOX_POSITION: Vector3 = Vector3(3.0, 0.0, 8.0)

const FLOOR_SIZE: Vector3 = Vector3(200.0, 1.0, 200.0)
const STEP_HEIGHT: float = 0.2
const STEP_DEPTH: float = 0.4
const STEP_WIDTH: float = 3.0
const STEP_COUNT: int = 10
const CORRIDOR_WIDTH: float = 0.8
const TUNNEL_HEIGHT: float = 1.0
const WALL_HEIGHTS: Array[float] = [1.0, 1.5, 2.0, 3.0]
const RAMP_ANGLES: Array[float] = [15.0, 30.0, 45.0]
const TARGET_DISTANCES: Array[int] = [10, 25, 50, 100, 200]
# Мишени TargetDummy: первые DUMMY_STANDING_COUNT стоят, остальные патрулируют на DUMMY_PATROL_OFFSET.
const DUMMY_POSITIONS: Array[Vector3] = [
	Vector3(-8.0, 0.0, 3.0), Vector3(-4.0, 0.0, 3.0), Vector3(3.0, 0.0, 2.0),
	Vector3(-9.0, 0.0, -2.0), Vector3(8.0, 0.0, 2.0),
]
const DUMMY_STANDING_COUNT: int = 3
const DUMMY_PATROL_OFFSET: Vector3 = Vector3(6.0, 0.0, 0.0)
const DUMMY_PATROL_SPEEDS: Array[float] = [3.0, 4.0]


func _initialize() -> void:
	var root: Node3D = _build_testbed_scene()
	_set_owner_recursive(root, root)
	var packed: PackedScene = PackedScene.new()
	var pack_err: Error = packed.pack(root)
	root.free()
	if pack_err != OK:
		printerr("GEN_TESTBED FAIL pack: ", pack_err)
		quit(1)
		return
	var save_err: Error = ResourceSaver.save(packed, OUTPUT_PATH)
	if save_err != OK:
		printerr("GEN_TESTBED FAIL save: ", save_err)
		quit(1)
		return
	print("GEN_TESTBED OK: ", OUTPUT_PATH)
	quit(0)


func _build_testbed_scene() -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Testbed"
	var grid_shader: Shader = load(GRID_SHADER_PATH) as Shader
	var floor_mat: ShaderMaterial = _create_grid_material(grid_shader, Color(0.28, 0.30, 0.32))
	var obstacle_mat: ShaderMaterial = _create_grid_material(grid_shader, Color(0.42, 0.45, 0.48))
	var target_mat: StandardMaterial3D = _create_target_material()
	_add_environment_and_light(root)
	_add_player_spawn(root)
	_add_floor(root, floor_mat)
	var obstacles: Node3D = Node3D.new()
	obstacles.name = "Obstacles"
	root.add_child(obstacles)
	_add_walls(obstacles, obstacle_mat)
	_add_ramps(obstacles, obstacle_mat)
	_add_stairs(obstacles, obstacle_mat)
	_add_corridor(obstacles, obstacle_mat)
	_add_tunnel(obstacles, obstacle_mat)
	_add_shooting_range(root, floor_mat, obstacle_mat, target_mat)
	_add_target_dummies(root)
	_add_ui(root)
	var box: AmmoBox = (load(AMMO_BOX_PATH) as PackedScene).instantiate() as AmmoBox
	box.position = AMMO_BOX_POSITION
	root.add_child(box)
	return root


func _create_grid_material(shader: Shader, base_color: Color) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_color", base_color)
	mat.set_shader_parameter("grid_step", 1.0)
	return mat


func _create_target_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.28, 0.18)
	mat.roughness = 0.6
	return mat


func _add_environment_and_light(root: Node3D) -> void:
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env: Environment = Environment.new()
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	world_env.environment = env
	root.add_child(world_env)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.shadow_enabled = true
	sun.position = Vector3(0.0, 30.0, 0.0)
	sun.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	root.add_child(sun)


func _add_player_spawn(root: Node3D) -> void:
	var spawn: Marker3D = Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector3(0.0, 0.1, 10.0)
	root.add_child(spawn)

	var cam: Camera3D = Camera3D.new()
	cam.name = "PreviewCamera"
	cam.current = false
	cam.position = Vector3(-18.0, 12.0, 18.0)
	cam.rotation_degrees = Vector3(-25.0, -35.0, 0.0)
	root.add_child(cam)

	var player_packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	if player_packed != null:
		var player: Node3D = player_packed.instantiate() as Node3D
		player.name = "Player"
		player.position = spawn.position
		root.add_child(player)


func _add_floor(root: Node3D, mat: Material) -> void:
	var pos: Vector3 = Vector3(0.0, -FLOOR_SIZE.y * 0.5, 0.0)
	root.add_child(_create_static_box("Floor", FLOOR_SIZE, pos, Vector3.ZERO, mat))


func _add_walls(parent: Node3D, mat: Material) -> void:
	for i: int in range(WALL_HEIGHTS.size()):
		var h: float = WALL_HEIGHTS[i]
		var wall_name: String = "Wall_%s" % [str(h).replace(".", "_") + "m"]
		var size: Vector3 = Vector3(4.0, h, 0.5)
		var pos: Vector3 = Vector3(-20.0, h * 0.5, -float(i) * 5.0)
		parent.add_child(_create_static_box(wall_name, size, pos, Vector3.ZERO, mat))


func _add_ramps(parent: Node3D, mat: Material) -> void:
	var ramp_len: float = 6.0
	var ramp_thick: float = 0.4
	for i: int in range(RAMP_ANGLES.size()):
		var angle_deg: float = RAMP_ANGLES[i]
		var angle_rad: float = deg_to_rad(angle_deg)
		var ramp_name: String = "Ramp_%ddeg" % int(angle_deg)
		var y_center: float = (ramp_len * 0.5) * sin(angle_rad) - (ramp_thick * 0.5) * cos(angle_rad)
		var pos: Vector3 = Vector3(-10.0 + float(i) * 5.0, y_center, -12.0)
		var rot: Vector3 = Vector3(angle_deg, 0.0, 0.0)
		var size: Vector3 = Vector3(3.0, ramp_thick, ramp_len)
		parent.add_child(_create_static_box(ramp_name, size, pos, rot, mat))


func _add_stairs(parent: Node3D, mat: Material) -> void:
	var base_x: float = 6.0
	var base_z: float = -6.0
	for i: int in range(STEP_COUNT):
		var h: float = STEP_HEIGHT * float(i + 1)
		var step_name: String = "StairStep_%02d" % (i + 1)
		var size: Vector3 = Vector3(STEP_WIDTH, h, STEP_DEPTH)
		var pos: Vector3 = Vector3(base_x, h * 0.5, base_z - float(i) * STEP_DEPTH)
		parent.add_child(_create_static_box(step_name, size, pos, Vector3.ZERO, mat))


func _add_corridor(parent: Node3D, mat: Material) -> void:
	var wall_thick: float = 0.4
	var wall_height: float = 2.5
	var wall_len: float = 8.0
	var center_x: float = 12.0
	var center_z: float = -10.0
	var offset_x: float = CORRIDOR_WIDTH * 0.5 + wall_thick * 0.5
	var size: Vector3 = Vector3(wall_thick, wall_height, wall_len)
	parent.add_child(_create_static_box(
		"Corridor_WallLeft", size, Vector3(center_x - offset_x, wall_height * 0.5, center_z), Vector3.ZERO, mat
	))
	parent.add_child(_create_static_box(
		"Corridor_WallRight", size, Vector3(center_x + offset_x, wall_height * 0.5, center_z), Vector3.ZERO, mat
	))


func _add_tunnel(parent: Node3D, mat: Material) -> void:
	var wall_thick: float = 0.4
	var inner_width: float = 1.6
	var tunnel_len: float = 8.0
	var center_x: float = 18.0
	var center_z: float = -10.0
	var offset_x: float = inner_width * 0.5 + wall_thick * 0.5
	var side_size: Vector3 = Vector3(wall_thick, TUNNEL_HEIGHT, tunnel_len)
	var roof_size: Vector3 = Vector3(inner_width + wall_thick * 2.0, wall_thick, tunnel_len)
	parent.add_child(_create_static_box(
		"Tunnel_WallLeft", side_size, Vector3(center_x - offset_x, TUNNEL_HEIGHT * 0.5, center_z), Vector3.ZERO, mat
	))
	parent.add_child(_create_static_box(
		"Tunnel_WallRight", side_size, Vector3(center_x + offset_x, TUNNEL_HEIGHT * 0.5, center_z), Vector3.ZERO, mat
	))
	parent.add_child(_create_static_box(
		"Tunnel_Roof", roof_size, Vector3(center_x, TUNNEL_HEIGHT + wall_thick * 0.5, center_z), Vector3.ZERO, mat
	))


func _add_shooting_range(root: Node3D, floor_mat: Material, booth_mat: Material, target_mat: Material) -> void:
	var range_node: Node3D = Node3D.new()
	range_node.name = "ShootingRange"
	range_node.position = Vector3(35.0, 0.0, 95.0)
	root.add_child(range_node)

	var firing_line: Marker3D = Marker3D.new()
	firing_line.name = "FiringLine"
	range_node.add_child(firing_line)

	range_node.add_child(_create_static_box(
		"RangeFloorExtension", Vector3(24.0, 1.0, 20.0), Vector3(0.0, -0.5, -195.0), Vector3.ZERO, floor_mat
	))
	range_node.add_child(_create_static_box(
		"ShootingBench", Vector3(2.0, 1.1, 1.0), Vector3(-6.0, 0.55, 0.0), Vector3.ZERO, booth_mat
	))

	for i: int in range(TARGET_DISTANCES.size()):
		var dist: int = TARGET_DISTANCES[i]
		var t_name: String = "Target_%dm" % dist
		var x_offset: float = (float(i) - 2.0) * 2.5
		var size: Vector3 = Vector3(1.0, 1.8, 0.2)
		var pos: Vector3 = Vector3(x_offset, size.y * 0.5, -float(dist))
		range_node.add_child(_create_static_box(t_name, size, pos, Vector3.ZERO, target_mat))


func _create_static_box(
	node_name: String, size: Vector3, pos: Vector3, rot_deg: Vector3, mat: Material
) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.rotation_degrees = rot_deg
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0

	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = size
	col.shape = box_shape
	body.add_child(col)

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = size
	mesh_inst.mesh = box_mesh
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)
	return body


func _add_target_dummies(root: Node3D) -> void:
	var targets_root: Node3D = Node3D.new()
	targets_root.name = "Targets"
	root.add_child(targets_root)
	var dummy_packed: PackedScene = load(TARGET_DUMMY_SCENE_PATH) as PackedScene
	if dummy_packed == null:
		return
	for i: int in range(DUMMY_POSITIONS.size()):
		var dummy: TargetDummy = dummy_packed.instantiate() as TargetDummy
		dummy.name = "TargetDummy_%02d" % (i + 1)
		dummy.position = DUMMY_POSITIONS[i]
		var patrol_idx: int = i - DUMMY_STANDING_COUNT
		if patrol_idx >= 0:
			var p0: Vector3 = DUMMY_POSITIONS[i]
			var points: PackedVector3Array = PackedVector3Array([p0, p0 + DUMMY_PATROL_OFFSET])
			dummy.set_patrol_path(points, DUMMY_PATROL_SPEEDS[patrol_idx])
		targets_root.add_child(dummy)


func _add_ui(root: Node3D) -> void:
	var hud_packed: PackedScene = load(HUD_SCENE_PATH) as PackedScene
	if hud_packed != null:
		var hud: Node = hud_packed.instantiate()
		hud.name = "HUD"
		root.add_child(hud)
	var overlay_packed: PackedScene = load(DEBUG_OVERLAY_SCENE_PATH) as PackedScene
	if overlay_packed != null:
		var overlay: Node = overlay_packed.instantiate()
		overlay.name = "DebugOverlay"
		root.add_child(overlay)


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		if child.scene_file_path.is_empty():
			_set_owner_recursive(child, owner_node)
