# Набор зон хитбоксов игрока (голова, торс, руки, ноги), подстраиваемых под размер капсулы и стойку.
class_name PlayerHitboxes
extends Node3D

const DEFAULT_HITBOX_CONFIG_PATH: String = "res://src/player/default_hitboxes.tres"
const DEFAULT_MOVEMENT_CONFIG_PATH: String = "res://src/player/default_movement.tres"

@export var hitbox_config: HitboxConfig = preload(DEFAULT_HITBOX_CONFIG_PATH)

var head_zone: HitboxZone = null
var torso_zone: HitboxZone = null
var left_arm_zone: HitboxZone = null
var right_arm_zone: HitboxZone = null
var legs_zone: HitboxZone = null

var _movement_config: MovementConfig = null
var _health_component: HealthComponent = null
var _body: CollisionObject3D = null
var _head_shape: SphereShape3D = null
var _torso_shape: BoxShape3D = null
var _left_arm_shape: BoxShape3D = null
var _right_arm_shape: BoxShape3D = null
var _legs_shape: BoxShape3D = null
var _zones: Array[HitboxZone] = []
var _exclude_rids: Array[RID] = []
var _zones_initialized: bool = false


func _ready() -> void:
	if hitbox_config == null:
		hitbox_config = load(DEFAULT_HITBOX_CONFIG_PATH) as HitboxConfig
	_ensure_zones()


func setup(
	body: CollisionObject3D,
	health_component: HealthComponent,
	movement_config: MovementConfig,
	custom_hitbox_config: HitboxConfig = null,
	initial_stance: int = PlayerStance.STAND
) -> void:
	_body = body
	_health_component = health_component
	_movement_config = movement_config
	if _movement_config == null:
		_movement_config = load(DEFAULT_MOVEMENT_CONFIG_PATH) as MovementConfig
	if custom_hitbox_config != null:
		hitbox_config = custom_hitbox_config
	elif hitbox_config == null:
		hitbox_config = load(DEFAULT_HITBOX_CONFIG_PATH) as HitboxConfig
	_ensure_zones()
	_configure_all_zones()
	_rebuild_exclude_rids()
	update_for_stance(initial_stance, 0.0)


func update_for_stance(stance: int, lean_offset: float = 0.0) -> void:
	if _movement_config == null:
		_movement_config = load(DEFAULT_MOVEMENT_CONFIG_PATH) as MovementConfig
	var cap_h: float = _movement_config.capsule_height_for(stance)
	var head_h: float = _movement_config.head_height_for(stance)
	update_for_dimensions(cap_h, head_h, lean_offset)


func update_for_dimensions(
	capsule_height: float,
	head_height: float,
	lean_offset: float = 0.0
) -> void:
	_ensure_zones()
	var cfg: HitboxConfig = hitbox_config
	var head_r: float = minf(cfg.head_radius, capsule_height * cfg.head_radius_max_height_ratio)
	_head_shape.radius = head_r
	head_zone.position = Vector3(lean_offset, head_height, 0.0)

	var body_top: float = maxf(head_height - head_r, cfg.min_body_height)
	var legs_h: float = maxf(body_top * cfg.legs_height_ratio, cfg.min_body_height * 0.5)
	var torso_h: float = maxf(body_top - legs_h, cfg.min_body_height * 0.5)

	_torso_shape.size = Vector3(cfg.torso_width, torso_h, cfg.torso_depth)
	torso_zone.position = Vector3(0.0, legs_h + torso_h * 0.5, 0.0)

	var arm_h: float = maxf(torso_h * cfg.arm_height_ratio, cfg.min_body_height * 0.5)
	var arm_x: float = (cfg.torso_width + cfg.arm_width) * 0.5 + cfg.arm_gap
	var arm_y: float = legs_h + torso_h * 0.5
	var arm_size: Vector3 = Vector3(cfg.arm_width, arm_h, cfg.arm_depth)
	_left_arm_shape.size = arm_size
	_right_arm_shape.size = arm_size
	left_arm_zone.position = Vector3(-arm_x, arm_y, 0.0)
	right_arm_zone.position = Vector3(arm_x, arm_y, 0.0)

	_legs_shape.size = Vector3(cfg.legs_width, legs_h, cfg.legs_depth)
	legs_zone.position = Vector3(0.0, legs_h * 0.5, 0.0)


func get_zones() -> Array[HitboxZone]:
	return _zones


func get_exclude_rids() -> Array[RID]:
	if _exclude_rids.is_empty():
		_rebuild_exclude_rids()
	return _exclude_rids


func _ensure_zones() -> void:
	# Поиск узлов и отделение форм от ресурсов сцены выполняются только один раз.
	if _zones_initialized:
		return
	if hitbox_config == null:
		hitbox_config = load(DEFAULT_HITBOX_CONFIG_PATH) as HitboxConfig
	head_zone = _get_or_create_zone("HeadZone", HitboxZone.HEAD)
	torso_zone = _get_or_create_zone("TorsoZone", HitboxZone.TORSO)
	left_arm_zone = _get_or_create_zone("LeftArmZone", HitboxZone.ARMS)
	right_arm_zone = _get_or_create_zone("RightArmZone", HitboxZone.ARMS)
	legs_zone = _get_or_create_zone("LegsZone", HitboxZone.LEGS)
	_head_shape = _ensure_sphere_shape(head_zone)
	_torso_shape = _ensure_box_shape(torso_zone)
	_left_arm_shape = _ensure_box_shape(left_arm_zone)
	_right_arm_shape = _ensure_box_shape(right_arm_zone)
	_legs_shape = _ensure_box_shape(legs_zone)
	_zones = [head_zone, torso_zone, left_arm_zone, right_arm_zone, legs_zone]
	_zones_initialized = true


func _get_or_create_zone(zone_name: String, zone_type: int) -> HitboxZone:
	var z: HitboxZone = get_node_or_null(zone_name) as HitboxZone
	if z == null:
		z = HitboxZone.new()
		z.name = zone_name
		add_child(z)
	var col: CollisionShape3D = z.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null:
		col = CollisionShape3D.new()
		col.name = "CollisionShape3D"
		z.add_child(col)
	z.zone = zone_type
	z.damage_mult = hitbox_config.multiplier_for(zone_type)
	z.health_component = _health_component
	return z


func _ensure_sphere_shape(z: HitboxZone) -> SphereShape3D:
	var col: CollisionShape3D = z.get_node("CollisionShape3D") as CollisionShape3D
	if col.shape is SphereShape3D:
		var dup: SphereShape3D = (col.shape as SphereShape3D).duplicate() as SphereShape3D
		col.shape = dup
		return dup
	var sphere: SphereShape3D = SphereShape3D.new()
	col.shape = sphere
	return sphere


func _ensure_box_shape(z: HitboxZone) -> BoxShape3D:
	var col: CollisionShape3D = z.get_node("CollisionShape3D") as CollisionShape3D
	if col.shape is BoxShape3D:
		var dup: BoxShape3D = (col.shape as BoxShape3D).duplicate() as BoxShape3D
		col.shape = dup
		return dup
	var box: BoxShape3D = BoxShape3D.new()
	col.shape = box
	return box


func _configure_all_zones() -> void:
	for z: HitboxZone in _zones:
		z.configure(z.zone, hitbox_config.multiplier_for(z.zone), _health_component)


func _rebuild_exclude_rids() -> void:
	_exclude_rids.clear()
	if _body != null:
		_exclude_rids.append(_body.get_rid())
	for z: HitboxZone in _zones:
		if z != null:
			_exclude_rids.append(z.get_rid())
