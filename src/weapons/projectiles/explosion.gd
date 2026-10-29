# Однократный радиальный урон по уникальным владельцам хитбоксов, без множителей головы.
class_name Explosion
extends Node3D

signal damage_applied(health: HealthComponent, amount: float, attacker: int)

const MAX_QUERY_RESULTS: int = 4096

var _shape: SphereShape3D = SphereShape3D.new()
var _query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
var _sight: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _targets: Dictionary[HealthComponent, HitboxZone] = {}


func _init() -> void:
	_query.shape = _shape
	_query.collision_mask = HitboxZone.LAYER_HITBOXES
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	_sight.hit_from_inside = true


func apply(profile: ProjectileData, point: Vector3, attacker: int) -> void:
	if not multiplayer.is_server() or profile.radius <= 0.0 or profile.damage <= 0.0:
		return
	_shape.radius = profile.radius
	_query.transform = Transform3D(Basis.IDENTITY, point)
	_targets.clear()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var hits: Array[Dictionary] = space.intersect_shape(_query, MAX_QUERY_RESULTS)
	for hit: Dictionary in hits:
		var zone: HitboxZone = hit.get("collider") as HitboxZone
		if zone == null or not is_instance_valid(zone.health_component):
			continue
		var health: HealthComponent = zone.health_component
		if not _targets.has(health) or zone.zone == HitboxZone.TORSO:
			_targets[health] = zone
	for health: HealthComponent in _targets:
		if not is_instance_valid(health) or not health.can_receive_damage():
			continue
		var target: Vector3 = _targets[health].global_position
		var amount: float = profile.damage_at(point.distance_to(target),
			has_line_of_sight(point, target, profile.occlusion_mask))
		if amount > 0.0:
			health.apply_damage(amount, attacker, HitboxZone.NONE, profile.id, point)
			damage_applied.emit(health, amount, attacker)


func has_line_of_sight(point: Vector3, target: Vector3, mask: int) -> bool:
	if point.is_equal_approx(target):
		return true
	_sight.from = point
	_sight.to = target
	_sight.collision_mask = mask
	return get_world_3d().direct_space_state.intersect_ray(_sight).is_empty()
