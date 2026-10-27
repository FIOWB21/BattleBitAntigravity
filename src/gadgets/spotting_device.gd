# Серверный луч приобретает цель; дальнейшая HUD-метка не требует LOS.
class_name SpottingDevice
extends Node3D

var _ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()


func _init() -> void:
	_ray.collision_mask = 1 | 4 | 16 | 64
	_ray.collide_with_areas = true
	_ray.hit_from_inside = true


func use(gadget: Gadget, ctx: GadgetContext, observer: CombatAffiliation,
		aim: Transform3D, registry: SpotRegistry, exclude: Array[RID]) -> bool:
	var data: SpottingData = gadget.data as SpottingData
	if not Game.is_server_or_offline(multiplayer) or data == null or not data.is_valid() \
			or not observer.is_alive() or not gadget.can_use() or not aim.is_finite():
		return false
	_ray.from = aim.origin
	_ray.to = aim.origin - aim.basis.z * data.reach
	_ray.exclude = exclude
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(_ray)
	var zone: HitboxZone = hit.get("collider") as HitboxZone
	if zone == null:
		return false
	var target: CombatAffiliation = CombatAffiliation.from_health(zone.health_component)
	if not registry.can_spot(target, observer.team_id) or not gadget.use(ctx):
		return false
	return registry.spot(target, observer.team_id, data.duration)
