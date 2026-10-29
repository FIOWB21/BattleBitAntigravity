# Серверная симуляция ножа: один запрос в момент контакта, без кадровой логики.
class_name MeleeAttack
extends Node3D

signal attack_started()
signal attack_finished()
signal hit_landed(target: HealthComponent, damage: float, backstab: bool)

const COLLISION_MASK: int = HitscanQuery.DEFAULT_COLLISION_MASK | (1 << 4) | (1 << 6)

@export var data: MeleeData = preload("res://src/weapons/data/knife.tres")

var busy: bool = false
var _last_tick: int = -1
var _hit_tick: int = -1
var _end_tick: int = -1
var _next_tick: int = 0
var _attacker: int = 0
var _query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()


func setup(attacker: int, exclude: Array[RID]) -> void:
	_attacker = attacker
	_query.exclude = exclude
	_query.collision_mask = COLLISION_MASK
	_query.collide_with_areas = true
	_query.collide_with_bodies = true
	_query.hit_from_inside = true


func simulate(inp: PlayerInput, aim: Transform3D, attacker_position: Vector3,
		alive: bool = true, allowed: bool = true) -> void:
	if not is_inside_tree() or not multiplayer.is_server() or inp.tick <= _last_tick:
		return
	_last_tick = inp.tick
	if not alive or data == null:
		_finish()
		return
	if busy:
		if _hit_tick >= 0 and inp.tick >= _hit_tick:
			_hit_tick = -1
			_strike(aim, attacker_position)
		if inp.tick >= _end_tick:
			_finish()
	if busy or not allowed or not inp.melee or inp.tick < _next_tick:
		return
	busy = true
	_hit_tick = inp.tick + _ticks(data.hit_delay)
	_end_tick = inp.tick + _ticks(maxf(data.duration, data.hit_delay))
	_next_tick = inp.tick + _ticks(maxf(data.interval, data.duration))
	attack_started.emit()


func _ticks(seconds: float) -> int:
	return maxi(1, ceili(seconds * Engine.physics_ticks_per_second))


func _finish() -> void:
	if not busy:
		return
	busy = false
	_hit_tick = -1
	attack_finished.emit()


func _strike(aim: Transform3D, attacker_position: Vector3) -> void:
	_query.from = aim.origin
	_query.to = aim.origin - aim.basis.z.normalized() * data.reach
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(_query)
	var zone: HitboxZone = hit.get("collider") as HitboxZone
	if zone == null or zone.health_component == null or not zone.health_component.can_receive_damage():
		return
	var entity: Node3D = zone.get_entity() as Node3D
	var backstab: bool = entity != null and data.is_backstab(attacker_position, entity.global_transform)
	var health: HealthComponent = zone.health_component
	var damage: float = maxf(health.current, data.damage) if backstab else maxf(data.damage, 0.0)
	if damage <= 0.0:
		return
	health.apply_damage(damage, _attacker, zone.zone, data.id, aim.origin)
	hit_landed.emit(health, damage, backstab)
