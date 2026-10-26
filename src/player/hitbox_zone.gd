# Зона хитбокса (Area3D на слое hitboxes) с типом зоны, множителем урона и ссылкой на HealthComponent.
class_name HitboxZone
extends Area3D

enum Zone {
	NONE = -1,
	HEAD = 0,
	TORSO = 1,
	ARMS = 2,
	LEGS = 3,
}

const NONE: int = Zone.NONE
const HEAD: int = Zone.HEAD
const TORSO: int = Zone.TORSO
const ARMS: int = Zone.ARMS
const LEGS: int = Zone.LEGS

const LAYER_HITBOXES: int = 1 << 2

@export var zone: int = HEAD
@export var damage_mult: float = 1.0
@export var health_component: HealthComponent = null

var owner_health: HealthComponent:
	get:
		return health_component
	set(value):
		health_component = value


func _init() -> void:
	collision_layer = LAYER_HITBOXES
	collision_mask = 0
	monitoring = false
	monitorable = true


func _ready() -> void:
	collision_layer = LAYER_HITBOXES
	collision_mask = 0
	monitoring = false
	monitorable = true


func configure(
	zone_type: int,
	multiplier: float,
	owner_hc: HealthComponent
) -> void:
	zone = zone_type
	damage_mult = multiplier
	health_component = owner_hc
	collision_layer = LAYER_HITBOXES
	collision_mask = 0
	monitoring = false
	monitorable = true


func apply_damage(base_damage: float, source_id: int = 0) -> float:
	if base_damage <= 0.0:
		return 0.0
	var final_damage: float = base_damage * maxf(damage_mult, 0.0)
	if health_component != null and final_damage > 0.0:
		health_component.apply_damage(final_damage, source_id, zone)
	return final_damage


func get_entity() -> Node:
	if health_component != null and health_component.get_parent() != null:
		return health_component.get_parent()
	return get_parent()
