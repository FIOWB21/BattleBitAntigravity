# Аналитическое решение dv/dt = gravity - drag * v для постоянного шага.
class_name ProjectileBallistics
extends RefCounted


static func velocity_after(velocity: Vector3, data: ProjectileData, delta: float) -> Vector3:
	if data.drag <= 0.0:
		return velocity + data.gravity * delta
	var terminal: Vector3 = data.gravity / data.drag
	return terminal + (velocity - terminal) * exp(-data.drag * delta)


static func displacement(velocity: Vector3, data: ProjectileData, delta: float) -> Vector3:
	if data.drag <= 0.0:
		return velocity * delta + data.gravity * delta * delta * 0.5
	var terminal: Vector3 = data.gravity / data.drag
	return terminal * delta + (velocity - terminal) * (1.0 - exp(-data.drag * delta)) / data.drag


static func bounced(velocity: Vector3, normal: Vector3, data: ProjectileData) -> Vector3:
	var normal_speed: float = velocity.dot(normal)
	if normal_speed >= 0.0:
		return velocity
	var tangent: Vector3 = velocity - normal * normal_speed
	return tangent * (1.0 - data.friction) - normal * normal_speed * data.restitution
