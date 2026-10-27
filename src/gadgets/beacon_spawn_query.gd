# Только команда возрождения: луч земли, проход от маяка, полный стоячий объём.
class_name BeaconSpawnQuery
extends RefCounted

var pose: Transform3D = Transform3D.IDENTITY
var _ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _shape: CapsuleShape3D = CapsuleShape3D.new()
var _query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
var _exclude: Array[RID] = []


func _init() -> void:
	_ray.hit_from_inside = true
	_query.shape = _shape


func solve(player: Player, origin: Transform3D, config: BeaconConfig) -> bool:
	if config == null or not config.is_valid() or not origin.is_finite():
		return false
	_shape.radius = player.movement_config.capsule_radius
	_shape.height = player.movement_config.stand_height
	_exclude.clear()
	_exclude.append(player.get_rid())
	_query.exclude = _exclude
	_query.collision_mask = config.clearance_mask
	_ray.collision_mask = config.ground_mask
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for offset: Vector3 in config.offsets:
		if _candidate(space, origin, offset, config):
			return true
	return false


func _candidate(space: PhysicsDirectSpaceState3D, origin: Transform3D,
		offset: Vector3, config: BeaconConfig) -> bool:
	var ahead: Vector3 = origin * offset
	_ray.from = ahead + Vector3.UP * config.probe_up
	_ray.to = ahead - Vector3.UP * config.probe_down
	var hit: Dictionary = space.intersect_ray(_ray)
	if hit.is_empty() or (hit.normal as Vector3).dot(Vector3.UP) < config.min_up_dot:
		return false
	var feet: Vector3 = hit.position + Vector3.UP * config.floor_margin
	_ray.from = origin.origin + Vector3.UP * (_shape.height * 0.5)
	_ray.to = feet + Vector3.UP * (_shape.height * 0.5)
	if not space.intersect_ray(_ray).is_empty():
		return false
	_query.transform = Transform3D(Basis.IDENTITY, _ray.to)
	if not space.intersect_shape(_query, 1).is_empty():
		return false
	pose = Transform3D(Basis(Vector3.UP, origin.basis.get_euler().y), feet)
	return true
