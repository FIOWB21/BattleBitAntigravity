# Тренировочная мишень (стоячая или движущаяся по точкам маршрута) с HealthComponent, хитбоксами и автореспавном.
class_name TargetDummy
extends Node3D

signal health_changed(current: float, max_value: float)
signal died(killer_id: int)
signal respawned()

const DEFAULT_MOVEMENT_PATH: String = "res://src/player/default_movement.tres"
const DEFAULT_HITBOXES_PATH: String = "res://src/player/default_hitboxes.tres"
const WAYPOINT_EPSILON: float = 0.005
const MIN_WAYPOINTS: int = 2

@export var max_health: float = 100.0:
	set(value):
		max_health = maxf(value, 1.0)
		if health_component != null:
			health_component.max_health = max_health

@export var respawn_delay: float = 3.0
@export var move_enabled: bool = false
@export var move_speed: float = 3.0
@export var waypoints: PackedVector3Array = PackedVector3Array()
@export var movement_config: MovementConfig = preload(DEFAULT_MOVEMENT_PATH)
@export var hitbox_config: HitboxConfig = preload(DEFAULT_HITBOXES_PATH)

var is_dead: bool = false
var _respawn_timer: float = 0.0
var _waypoint_index: int = 0

@onready var health_component: HealthComponent = get_node_or_null("HealthComponent") as HealthComponent
@onready var hitboxes: PlayerHitboxes = get_node_or_null("Hitboxes") as PlayerHitboxes
@onready var visuals: Node3D = get_node_or_null("Visuals") as Node3D


func _ready() -> void:
	_setup_components()
	_connect_signals()


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if delta <= 0.0:
		return
	if is_dead:
		_respawn_timer = maxf(_respawn_timer - delta, 0.0)
		if _respawn_timer <= 0.0:
			respawn()
		return
	_step_movement(delta)


func apply_damage(amount: float, source_id: int = 0, zone: int = HitboxZone.TORSO) -> void:
	if health_component == null:
		_setup_components()
	health_component.apply_damage(amount, source_id, zone)


func respawn() -> void:
	is_dead = false
	_respawn_timer = 0.0
	if health_component != null:
		health_component.reset()
	_set_hitboxes_active(true)
	if visuals != null:
		visuals.visible = true
	respawned.emit()


func get_respawn_time_left() -> float:
	return _respawn_timer


func set_patrol_path(points: PackedVector3Array, speed: float) -> void:
	waypoints = points
	move_speed = speed
	move_enabled = points.size() >= MIN_WAYPOINTS
	_waypoint_index = 0


func _setup_components() -> void:
	if movement_config == null:
		movement_config = load(DEFAULT_MOVEMENT_PATH) as MovementConfig
	if hitbox_config == null:
		hitbox_config = load(DEFAULT_HITBOXES_PATH) as HitboxConfig
	if health_component == null:
		health_component = get_node_or_null("HealthComponent") as HealthComponent
	if health_component == null:
		health_component = HealthComponent.new()
		health_component.name = "HealthComponent"
		add_child(health_component)
	health_component.max_health = max_health
	if hitboxes == null:
		hitboxes = get_node_or_null("Hitboxes") as PlayerHitboxes
	if hitboxes == null:
		hitboxes = PlayerHitboxes.new()
		hitboxes.name = "Hitboxes"
		add_child(hitboxes)
	hitboxes.setup(null, health_component, movement_config, hitbox_config, PlayerStance.STAND)
	if visuals == null:
		visuals = get_node_or_null("Visuals") as Node3D


func _connect_signals() -> void:
	if health_component == null:
		return
	if not health_component.health_changed.is_connected(_on_health_changed):
		health_component.health_changed.connect(_on_health_changed)
	if not health_component.died.is_connected(_on_health_died):
		health_component.died.connect(_on_health_died)


func _on_health_changed(current: float, max_value: float) -> void:
	health_changed.emit(current, max_value)


func _on_health_died(killer_id: int) -> void:
	is_dead = true
	_respawn_timer = maxf(respawn_delay, 0.0)
	_set_hitboxes_active(false)
	if visuals != null:
		visuals.visible = false
	died.emit(killer_id)


func _set_hitboxes_active(active: bool) -> void:
	if hitboxes == null:
		return
	for zone_node: HitboxZone in hitboxes.get_zones():
		if zone_node == null:
			continue
		zone_node.collision_layer = HitboxZone.LAYER_HITBOXES if active else 0
		zone_node.monitorable = active
		var col: CollisionShape3D = zone_node.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if col != null:
			col.set_deferred("disabled", not active)


func _step_movement(delta: float) -> void:
	if not move_enabled or move_speed <= 0.0 or waypoints.size() < MIN_WAYPOINTS:
		return
	var target_pt: Vector3 = waypoints[_waypoint_index]
	position = position.move_toward(target_pt, move_speed * delta)
	if position.distance_to(target_pt) <= WAYPOINT_EPSILON:
		_waypoint_index = (_waypoint_index + 1) % waypoints.size()
