# Генератор сцены игрока res://src/player/player.tscn.
extends SceneTree

const OUTPUT_PATH: String = "res://src/player/player.tscn"
const PLAYER_SCRIPT_PATH: String = "res://src/player/player.gd"
const STANCE_CONTROLLER_SCRIPT_PATH: String = "res://src/player/stance_controller.gd"
const HEALTH_COMPONENT_SCRIPT_PATH: String = "res://src/core/health_component.gd"
const PLAYER_HITBOXES_SCRIPT_PATH: String = "res://src/player/player_hitboxes.gd"
const CAMERA_EFFECTS_SCRIPT_PATH: String = "res://src/player/camera_effects.gd"
const MOVEMENT_CONFIG_PATH: String = "res://src/player/default_movement.tres"
const HITBOX_CONFIG_PATH: String = "res://src/player/default_hitboxes.tres"

const LAYER_WORLD: int = 1 << 0
const LAYER_PLAYERS: int = 1 << 1

const CAPSULE_HEIGHT: float = 1.8
const CAPSULE_RADIUS: float = 0.35
const HEAD_HEIGHT: float = 1.65
const DEFAULT_CAMERA_FOV: float = 90.0


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

	_add_head_and_components(player)
	_add_weapon(player)
	return player


func _add_head_and_components(player: CharacterBody3D) -> void:
	var head: Node3D = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, HEAD_HEIGHT, 0.0)
	player.add_child(head)

	var cam: Camera3D = Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.fov = DEFAULT_CAMERA_FOV
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	head.add_child(cam)
	var ads_view: WeaponAdsView = WeaponAdsView.new()
	ads_view.name = "WeaponAdsView"
	cam.add_child(ads_view)

	var effects_script: GDScript = load(CAMERA_EFFECTS_SCRIPT_PATH) as GDScript
	var cam_effects: Node3D = effects_script.new() as Node3D
	cam_effects.name = "CameraEffects"
	head.add_child(cam_effects)

	var stance_script: GDScript = load(STANCE_CONTROLLER_SCRIPT_PATH) as GDScript
	var stance_ctrl: Node = stance_script.new() as Node
	stance_ctrl.name = "StanceController"
	player.add_child(stance_ctrl)

	var health_script: GDScript = load(HEALTH_COMPONENT_SCRIPT_PATH) as GDScript
	var health_comp: HealthComponent = health_script.new() as HealthComponent
	health_comp.name = "HealthComponent"
	player.add_child(health_comp)

	var hitboxes_script: GDScript = load(PLAYER_HITBOXES_SCRIPT_PATH) as GDScript
	var hitboxes: PlayerHitboxes = hitboxes_script.new() as PlayerHitboxes
	hitboxes.name = "Hitboxes"
	var hb_cfg: HitboxConfig = load(HITBOX_CONFIG_PATH) as HitboxConfig
	var mov_cfg: MovementConfig = load(MOVEMENT_CONFIG_PATH) as MovementConfig
	player.add_child(hitboxes)
	hitboxes.setup(player, health_comp, mov_cfg, hb_cfg, PlayerStance.STAND)


func _add_weapon(player: CharacterBody3D) -> void:
	var weapon: Weapon = Weapon.new()
	weapon.name = "Weapon"
	weapon.data = load("res://src/weapons/data/ar.tres") as WeaponData
	player.add_child(weapon)
	var hitscan: WeaponHitscan = WeaponHitscan.new()
	hitscan.name = "WeaponHitscan"
	player.add_child(hitscan)
	var receiver: AmmoReceiver = AmmoReceiver.new()
	receiver.name = "AmmoReceiver"
	receiver.weapon = weapon
	player.add_child(receiver)
	var click: WeaponDryFire = WeaponDryFire.new()
	click.name = "DryFire"
	weapon.add_child(click)


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		_set_owner_recursive(child, owner_node)
