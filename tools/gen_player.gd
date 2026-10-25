# Генератор сцены игрока res://src/player/player.tscn.
extends SceneTree

const OUTPUT_PATH: String = "res://src/player/player.tscn"
const PLAYER_SCRIPT_PATH: String = "res://src/player/player.gd"
const MOVEMENT_CONFIG_PATH: String = "res://src/player/default_movement.tres"

const LAYER_WORLD: int = 1 << 0
const LAYER_PLAYERS: int = 1 << 1

const CAPSULE_HEIGHT: float = 1.8
const CAPSULE_RADIUS: float = 0.35
const HEAD_HEIGHT: float = 1.6


func _initialize() -> void:
	var player: CharacterBody3D = _build_player_scene()
	_set_owner_recursive(player, player)
	var packed: PackedScene = PackedScene.new()
	var pack_err: Error = packed.pack(player)
	player.free()
	if pack_err != OK:
		printerr("GEN_PLAYER FAIL pack: ", pack_err)
		quit(1)
		return
	var save_err: Error = ResourceSaver.save(packed, OUTPUT_PATH)
	if save_err != OK:
		printerr("GEN_PLAYER FAIL save: ", save_err)
		quit(1)
		return
	print("GEN_PLAYER OK: ", OUTPUT_PATH)
	quit(0)


func _build_player_scene() -> CharacterBody3D:
	var player_script: GDScript = load(PLAYER_SCRIPT_PATH) as GDScript
	var player: CharacterBody3D = player_script.new() as CharacterBody3D
	player.name = "Player"
	player.collision_layer = LAYER_PLAYERS
	player.collision_mask = LAYER_WORLD
	var cfg: MovementConfig = load(MOVEMENT_CONFIG_PATH) as MovementConfig
	player.set("movement_config", cfg)
	player.floor_max_angle = deg_to_rad(cfg.max_slope_angle) + PlayerMotor.SLOPE_EPSILON_RAD

	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	col.position = Vector3(0.0, CAPSULE_HEIGHT * 0.5, 0.0)
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.height = CAPSULE_HEIGHT
	capsule.radius = CAPSULE_RADIUS
	col.shape = capsule
	player.add_child(col)

	var head: Node3D = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, HEAD_HEIGHT, 0.0)
	player.add_child(head)

	var cam: Camera3D = Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	head.add_child(cam)

	return player


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		_set_owner_recursive(child, owner_node)
