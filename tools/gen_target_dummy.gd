# Генератор сцены тренировочной мишени res://src/maps/testbed/target_dummy.tscn.
extends SceneTree

const OUTPUT_PATH: String = "res://src/maps/testbed/target_dummy.tscn"
const TARGET_DUMMY_SCRIPT_PATH: String = "res://src/maps/testbed/target_dummy.gd"
const HEALTH_COMPONENT_SCRIPT_PATH: String = "res://src/core/health_component.gd"
const PLAYER_HITBOXES_SCRIPT_PATH: String = "res://src/player/player_hitboxes.gd"
const MOVEMENT_CONFIG_PATH: String = "res://src/player/default_movement.tres"
const HITBOX_CONFIG_PATH: String = "res://src/player/default_hitboxes.tres"

const BODY_HEIGHT: float = 1.45
const BODY_RADIUS: float = 0.25
const HEAD_HEIGHT: float = 1.65
const HEAD_RADIUS: float = 0.15


func _initialize() -> void:
	var dummy: Node3D = _build_target_dummy_scene()
	_set_owner_recursive(dummy, dummy)
	var packed: PackedScene = PackedScene.new()
	var pack_err: Error = packed.pack(dummy)
	dummy.free()
	if pack_err != OK:
		printerr("GEN_TARGET_DUMMY FAIL pack: ", pack_err)
		quit(1)
		return
	var save_err: Error = ResourceSaver.save(packed, OUTPUT_PATH)
	if save_err != OK:
		printerr("GEN_TARGET_DUMMY FAIL save: ", save_err)
		quit(1)
		return
	print("GEN_TARGET_DUMMY OK: ", OUTPUT_PATH)
	quit(0)


func _build_target_dummy_scene() -> Node3D:
	var dummy_script: GDScript = load(TARGET_DUMMY_SCRIPT_PATH) as GDScript
	var dummy: Node3D = dummy_script.new() as Node3D
	dummy.name = "TargetDummy"

	var health_script: GDScript = load(HEALTH_COMPONENT_SCRIPT_PATH) as GDScript
	var health_comp: HealthComponent = health_script.new() as HealthComponent
	health_comp.name = "HealthComponent"
	dummy.add_child(health_comp)

	var hitboxes_script: GDScript = load(PLAYER_HITBOXES_SCRIPT_PATH) as GDScript
	var hitboxes: PlayerHitboxes = hitboxes_script.new() as PlayerHitboxes
	hitboxes.name = "Hitboxes"
	var hb_cfg: HitboxConfig = load(HITBOX_CONFIG_PATH) as HitboxConfig
	var mov_cfg: MovementConfig = load(MOVEMENT_CONFIG_PATH) as MovementConfig
	dummy.add_child(hitboxes)
	hitboxes.setup(null, health_comp, mov_cfg, hb_cfg, PlayerStance.STAND)

	_add_visuals(dummy)
	return dummy


func _add_visuals(dummy: Node3D) -> void:
	var visuals: Node3D = Node3D.new()
	visuals.name = "Visuals"
	dummy.add_child(visuals)

	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.85, 0.32, 0.22)
	body_mat.roughness = 0.55

	var head_mat: StandardMaterial3D = StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.95, 0.78, 0.22)
	head_mat.roughness = 0.45

	var body_mesh_inst: MeshInstance3D = MeshInstance3D.new()
	body_mesh_inst.name = "BodyMesh"
	body_mesh_inst.position = Vector3(0.0, BODY_HEIGHT * 0.5, 0.0)
	var cap_mesh: CapsuleMesh = CapsuleMesh.new()
	cap_mesh.height = BODY_HEIGHT
	cap_mesh.radius = BODY_RADIUS
	body_mesh_inst.mesh = cap_mesh
	body_mesh_inst.material_override = body_mat
	visuals.add_child(body_mesh_inst)

	var head_mesh_inst: MeshInstance3D = MeshInstance3D.new()
	head_mesh_inst.name = "HeadMesh"
	head_mesh_inst.position = Vector3(0.0, HEAD_HEIGHT, 0.0)
	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radius = HEAD_RADIUS
	sphere_mesh.height = HEAD_RADIUS * 2.0
	head_mesh_inst.mesh = sphere_mesh
	head_mesh_inst.material_override = head_mat
	visuals.add_child(head_mesh_inst)


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		_set_owner_recursive(child, owner_node)
