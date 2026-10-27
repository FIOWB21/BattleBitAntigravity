# Сигналы Area3D кешируют владельцев: пять хитбоксов не умножают эффект.
class_name GadgetAura
extends Area3D

var targets: Dictionary[HealthComponent, Node3D] = {}
var _zones: Dictionary[Area3D, HealthComponent] = {}
var _counts: Dictionary[HealthComponent, int] = {}

@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = HitboxZone.LAYER_HITBOXES
	monitorable = false
	area_entered.connect(track)
	area_exited.connect(untrack)
	_collision.shape = _collision.shape.duplicate()


func set_radius(radius: float) -> void:
	(_collision.shape as SphereShape3D).radius = radius


func track(area: Area3D) -> void:
	if not area is HitboxZone or _zones.has(area):
		return
	var health: HealthComponent = (area as HitboxZone).health_component
	if not is_instance_valid(health) or not health.get_parent() is Node3D:
		return
	if not targets.has(health):
		health.tree_exiting.connect(_forget_health.bind(health), CONNECT_ONE_SHOT)
	_zones[area] = health
	_counts[health] = _counts.get(health, 0) + 1
	targets[health] = health.get_parent() as Node3D


func untrack(area: Area3D) -> void:
	if not _zones.has(area):
		return
	var health: HealthComponent = _zones[area]
	_zones.erase(area)
	_counts[health] -= 1
	if _counts[health] == 0:
		_counts.erase(health)
		targets.erase(health)
		if is_instance_valid(health) and health.tree_exiting.is_connected(_forget_health.bind(health)):
			health.tree_exiting.disconnect(_forget_health.bind(health))


func _forget_health(health: HealthComponent) -> void:
	# Снимок ключей создаётся только при удалении цели, вне кадрового опроса.
	for area: Area3D in _zones.keys():
		if _zones[area] == health:
			_zones.erase(area)
	_counts.erase(health)
	targets.erase(health)


func contains_target(health: HealthComponent, center: Vector3, radius: float) -> bool:
	if not is_instance_valid(health) or health.is_dead or not targets.has(health):
		return false
	var entity: Node3D = targets[health]
	return is_instance_valid(entity) and not entity.is_queued_for_deletion() \
		and entity.global_position.distance_squared_to(center) <= radius * radius
