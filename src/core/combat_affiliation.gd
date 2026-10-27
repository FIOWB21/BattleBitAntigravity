# Минимальные серверные данные принадлежности, без назначения команд матча.
class_name CombatAffiliation
extends Node

const HEALTH_META: StringName = &"combat_affiliation"

@export var team_id: int = 1
@export var actor: Node3D
@export var health: HealthComponent


func _ready() -> void:
	if is_instance_valid(health):
		health.set_meta(HEALTH_META, self)


func _exit_tree() -> void:
	if is_instance_valid(health) and health.has_meta(HEALTH_META) and health.get_meta(HEALTH_META) == self:
		health.remove_meta(HEALTH_META)


func is_alive() -> bool:
	return is_instance_valid(actor) and not actor.is_queued_for_deletion() \
		and is_instance_valid(health) and not health.is_dead


static func from_health(component: HealthComponent) -> CombatAffiliation:
	if not is_instance_valid(component) or not component.has_meta(HEALTH_META):
		return null
	return component.get_meta(HEALTH_META) as CombatAffiliation
