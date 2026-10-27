# Непрерывный серверный инструмент. Пропуски тиков охлаждают, но не доремонтируют прошлое.
class_name RepairTool
extends Node3D

signal repaired(health: HealthComponent, amount: float)
signal overheat_started
signal overheat_finished
signal presentation_changed(working: bool, point: Vector3, heat: float, locked: bool)

const HEAT_EPSILON: float = 0.000001

@export var data: RepairToolData
@export var ticks_per_second: int = Engine.physics_ticks_per_second

var heat: float = 0.0
var overheated: bool = false
var is_repairing: bool = false
var hit_point: Vector3 = Vector3.ZERO
var view: RepairToolView
var _last_tick: int = -1
var _ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()


func setup(exclude: Array[RID]) -> void:
	_ray.exclude = exclude
	_ray.collide_with_areas = true
	_ray.collide_with_bodies = true
	_ray.hit_from_inside = true


func simulate(inp: PlayerInput, aim: Transform3D, allowed: bool) -> void:
	if not is_inside_tree() or not Game.is_server_or_offline(multiplayer):
		return
	if data == null or not data.is_valid() or ticks_per_second <= 0 or inp.tick <= _last_tick:
		return
	var delta: float = 1.0 / ticks_per_second
	if _last_tick >= 0 and inp.tick > _last_tick + 1:
		_cool((inp.tick - _last_tick - 1) * delta)
	_last_tick = inp.tick
	is_repairing = false
	if overheated:
		_cool(delta)
	else:
		var surface: RepairSurface
		if allowed and inp.pressed(PlayerInput.BTN_FIRE) and aim.is_finite():
			surface = _trace(aim)
		if surface != null:
			_repair(surface, delta)
		else:
			_cool(delta)
	presentation_changed.emit(is_repairing, hit_point, heat, overheated)


func _trace(aim: Transform3D) -> RepairSurface:
	if aim.basis.z.length_squared() <= HEAT_EPSILON:
		return null
	_ray.from = aim.origin
	_ray.to = aim.origin - aim.basis.z.normalized() * data.reach
	_ray.collision_mask = data.ray_mask
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		return null
	var surface: RepairSurface = hit.get("collider") as RepairSurface
	if surface == null or not surface.can_repair():
		return null
	hit_point = hit.position
	return surface


func _repair(surface: RepairSurface, delta: float) -> void:
	var duration: float = minf(delta, (1.0 - heat) / data.heat_per_second)
	duration = minf(duration, (surface.health.max_health - surface.health.current) / data.repair_per_second)
	var amount: float = surface.repair(data.repair_per_second * duration)
	if amount <= 0.0:
		_cool(delta)
		return
	heat = minf(1.0, heat + duration * data.heat_per_second)
	is_repairing = true
	repaired.emit(surface.health, amount)
	if heat >= 1.0 - HEAT_EPSILON:
		heat = 1.0
		overheated = true
		is_repairing = false
		overheat_started.emit()


func _cool(delta: float) -> void:
	heat = maxf(0.0, heat - delta * data.cooling_per_second)
	if overheated and heat <= data.resume_heat + HEAT_EPSILON:
		overheated = false
		overheat_finished.emit()
