# Серверный сегментный снаряд; состояние переиспользуется пулом без физических тел.
class_name Projectile
extends Node3D

signal bounced(point: Vector3, normal: Vector3)
signal detonated(projectile: Projectile)

const FUSE_EPSILON: float = 0.000001

var active: bool = false
var data: ProjectileData
var velocity: Vector3 = Vector3.ZERO
var age: float = 0.0
var attacker: int = 0
var resting: bool = false
var _ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()


func launch(profile: ProjectileData, origin: Vector3, initial_velocity: Vector3,
		source: int = 0, exclude: Array[RID] = []) -> bool:
	if not multiplayer.is_server() or profile == null or profile.fuse <= 0.0:
		return false
	if not is_finite(profile.fuse) or profile.max_contacts < 1:
		return false
	if not origin.is_finite() or not initial_velocity.is_finite():
		return false
	data = profile
	global_position = origin
	velocity = initial_velocity
	attacker = source
	age = 0.0
	resting = false
	active = true
	_ray.exclude = exclude
	_ray.collision_mask = data.collision_mask
	_ray.collide_with_areas = (data.collision_mask & HitboxZone.LAYER_HITBOXES) != 0
	reset_physics_interpolation()
	return true


func simulate(delta: float) -> void:
	if not active or not multiplayer.is_server() or not is_finite(delta) or delta <= 0.0:
		return
	var duration: float = minf(delta, maxf(data.fuse - age, 0.0))
	if not resting:
		_travel(duration)
	age = minf(age + duration, data.fuse)
	if active and age >= data.fuse - FUSE_EPSILON:
		age = data.fuse
		_detonate()


func _travel(duration: float) -> void:
	var remaining: float = duration
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for contact: int in range(data.max_contacts):
		var movement: Vector3 = ProjectileBallistics.displacement(velocity, data, remaining)
		if movement.is_zero_approx():
			return
		_ray.from = global_position
		_ray.to = global_position + movement
		var hit: Dictionary = space.intersect_ray(_ray)
		if hit.is_empty():
			global_position = _ray.to
			velocity = ProjectileBallistics.velocity_after(velocity, data, remaining)
			return
		var point: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		var fraction: float = clampf(_ray.from.distance_to(point) / movement.length(), 0.0, 1.0)
		velocity = ProjectileBallistics.velocity_after(velocity, data, remaining * fraction)
		global_position = point + normal * data.contact_offset
		if data.impact_detonation:
			_detonate()
			return
		velocity = ProjectileBallistics.bounced(velocity, normal, data)
		bounced.emit(point, normal)
		if normal.dot(Vector3.UP) > data.rest_min_up_dot and velocity.length() <= data.rest_speed:
			velocity = Vector3.ZERO
			resting = true
			return
		remaining *= 1.0 - fraction
		if remaining <= 0.0:
			return
	# При исчерпании бюджета оставляем снаряд у последнего контакта, без туннелирования.


func _detonate() -> void:
	active = false
	detonated.emit(self)
