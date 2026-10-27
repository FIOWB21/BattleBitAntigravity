# Компонент ремонтируемой техники, независимый от физического типа её корня.
class_name RepairSurface
extends Area3D

const LAYER_VEHICLES: int = 1 << 4

@export var health: HealthComponent


func _ready() -> void:
	collision_layer = LAYER_VEHICLES
	collision_mask = 0
	monitoring = false
	monitorable = true


func can_repair() -> bool:
	return is_instance_valid(health) and not health.is_dead \
		and not health.is_queued_for_deletion() and health.current < health.max_health


func repair(amount: float) -> float:
	if not is_inside_tree() or not Game.is_server_or_offline(multiplayer) or not can_repair():
		return 0.0
	if not is_finite(amount) or amount <= 0.0:
		return 0.0
	var before: float = health.current
	health.heal(amount)
	return health.current - before
