# Луч до земли и проверка свободного объёма выполняются только по команде применения.
class_name GroundDeployment
extends RefCounted

var pose: Transform3D = Transform3D.IDENTITY
var _ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _shape: BoxShape3D = BoxShape3D.new()
var _query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()


func _init() -> void:
	_query.shape = _shape
	_ray.hit_from_inside = true


func solve(space: PhysicsDirectSpaceState3D, origin: Vector3, yaw: float,
		config: DeploymentConfig, exclude: Array[RID]) -> bool:
	if space == null or config == null or not config.is_valid() or not origin.is_finite() or not is_finite(yaw):
		return false
	var basis: Basis = Basis(Vector3.UP, yaw)
	var ahead: Vector3 = origin - basis.z * config.forward_distance
	_ray.from = ahead + Vector3.UP * config.probe_up
	_ray.to = ahead - Vector3.UP * config.probe_down
	_ray.collision_mask = config.collision_mask
	_ray.exclude = exclude
	var hit: Dictionary = space.intersect_ray(_ray)
	if hit.is_empty() or (hit.normal as Vector3).dot(Vector3.UP) < config.min_up_dot:
		return false
	# От тела до места размещения нельзя пройти лучом сквозь стену.
	var ground: Vector3 = hit.position
	_ray.from = origin + Vector3.UP * config.probe_up
	_ray.to = ground + Vector3.UP * config.probe_up
	if not space.intersect_ray(_ray).is_empty():
		return false
	_shape.size = config.clearance_size
	_query.collision_mask = config.collision_mask
	_query.exclude = exclude
	_query.transform = Transform3D(basis, ground + Vector3.UP * (
		config.clearance_size.y * 0.5 + config.clearance_offset))
	if not space.intersect_shape(_query, 1).is_empty():
		return false
	pose = Transform3D(basis, ground)
	return true
