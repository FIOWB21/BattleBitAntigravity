# Компонент здоровья сущности с поддержкой урона, лечения, смерти, респавна и опциональной регенерации.
class_name HealthComponent
extends Node

signal health_changed(current: float, max_value: float)
signal damaged(amount: float, source_id: int, zone: int)
signal died(killer_id: int)
signal finished_off(killer_id: int)
signal restored()

const DEFAULT_REGEN_RATE: float = 10.0

@export var max_health: float = 100.0:
	set(value):
		max_health = maxf(value, 1.0)
		if not is_dead and current <= 0.0:
			current = max_health
		elif current > max_health:
			current = max_health

@export var regen_enabled: bool = false:
	set(value):
		regen_enabled = value
		if regen_enabled and regen_rate <= 0.0:
			regen_rate = DEFAULT_REGEN_RATE

@export var regen_delay: float = 5.0
@export var regen_rate: float = 0.0:
	set(value):
		regen_rate = maxf(value, 0.0)
		if regen_rate > 0.0:
			regen_enabled = true

var current: float = 0.0
var is_dead: bool = false
var is_downed: bool = false
var _time_since_damage: float = 0.0


func _init() -> void:
	current = max_health


func _ready() -> void:
	current = max_health
	is_dead = false
	is_downed = false
	_time_since_damage = 0.0


func _physics_process(delta: float) -> void:
	step_regen(delta)


func apply_damage(amount: float, source_id: int = 0, zone: int = 0) -> void:
	if not _can_mutate() or not is_finite(amount) or amount <= 0.0:
		return
	if is_dead:
		if is_downed:
			is_downed = false
			finished_off.emit(source_id)
		return
	_time_since_damage = 0.0
	current = maxf(current - amount, 0.0)
	damaged.emit(amount, source_id, zone)
	health_changed.emit(current, max_health)
	if current <= 0.0:
		is_dead = true
		died.emit(source_id)


func take_damage(amount: float, source_id: int = 0, zone: int = 0) -> void:
	apply_damage(amount, source_id, zone)


func heal(amount: float) -> void:
	if not _can_mutate() or is_dead or not is_finite(amount) or amount <= 0.0:
		return
	current = minf(current + amount, max_health)
	health_changed.emit(current, max_health)


func reset() -> void:
	if not _can_mutate():
		return
	is_dead = false
	is_downed = false
	current = max_health
	_time_since_damage = 0.0
	health_changed.emit(current, max_health)
	restored.emit()


func restore_fraction(fraction: float) -> bool:
	if not _can_mutate() or not is_downed or not is_finite(fraction) or fraction <= 0.0 or fraction > 1.0:
		return false
	is_dead = false
	is_downed = false
	current = max_health * fraction
	_time_since_damage = 0.0
	health_changed.emit(current, max_health)
	restored.emit()
	return true


func can_receive_damage() -> bool:
	return not is_dead or is_downed


func _can_mutate() -> bool:
	return not is_inside_tree() or multiplayer.is_server()


func step_regen(delta: float) -> void:
	if is_dead or not regen_enabled or regen_rate <= 0.0 or delta <= 0.0:
		return
	if current >= max_health:
		return
	_time_since_damage += delta
	if _time_since_damage >= regen_delay:
		heal(regen_rate * delta)
