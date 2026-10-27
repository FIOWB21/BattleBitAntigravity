# Один урон на HealthComponent, даже если техника имеет несколько поверхностей/хитбоксов.
class_name ChargeBlast
extends Node3D

signal damage_applied(health: HealthComponent, amount: float, attacker: int)

var _shape: SphereShape3D = SphereShape3D.new()
var _query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
var _sight: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _targets: Dictionary[HealthComponent, Vector3] = {}
var _vehicles: Dictionary[HealthComponent, bool] = {}


func _init() -> void:
	_query.shape = _shape
	_query.collision_mask = HitboxZone.LAYER_HITBOXES | RepairSurface.LAYER_VEHICLES
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	_sight.hit_from_inside = true


func apply(config: ChargeConfig, point: Vector3, attacker: int) -> void:
	if not Game.is_server_or_offline(multiplayer) or config == null or not config.is_valid():
		return
	_shape.radius = config.blast.radius
	_query.transform = Transform3D(Basis.IDENTITY, point)
	_targets.clear()
	_vehicles.clear()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for hit: Dictionary in space.intersect_shape(_query, Explosion.MAX_QUERY_RESULTS):
		_track(hit.get("collider") as Area3D, int(hit.get("shape", 0)), point)
	for health: HealthComponent in _targets:
		if not is_instance_valid(health) or not health.can_receive_damage():
			continue
		var target: Vector3 = _targets[health]
		_sight.from = point
		_sight.to = target
		_sight.collision_mask = config.blast.occlusion_mask
		var visible_to_blast: bool = point.is_equal_approx(target) or space.intersect_ray(_sight).is_empty()
		var amount: float = config.blast.damage_at(point.distance_to(target), visible_to_blast)
		if _vehicles.has(health):
			amount *= config.vehicle_multiplier
		if amount > 0.0:
			health.apply_damage(amount, attacker, HitboxZone.NONE)
			damage_applied.emit(health, amount, attacker)


func _track(area: Area3D, shape_index: int, point: Vector3) -> void:
	var health: HealthComponent
	if area is RepairSurface:
		health = (area as RepairSurface).health
		if is_instance_valid(health):
			_vehicles[health] = true
	elif area is HitboxZone:
		health = (area as HitboxZone).health_component
	if is_instance_valid(health) and health.get_parent() is Node3D:
		var owner: int = area.shape_find_owner(shape_index)
		var target: Vector3 = area.global_transform * area.shape_owner_get_transform(owner).origin
		if not _targets.has(health) or point.distance_squared_to(target) < point.distance_squared_to(_targets[health]):
			_targets[health] = target
