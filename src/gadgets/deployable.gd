# Контракт размещаемого объекта. Сигналы жизненного цикла — граница репликации.
class_name Deployable
extends Node3D

signal deployed(tick: int)
signal despawned

var source_id: int = 0
var owner_id: int = 0
var team_id: int = 0
var squad_id: int = 0
var spawn_tick: int = -1
var _despawned: bool = false


static func spawn(scene: PackedScene, ctx: GadgetContext) -> Deployable:
	if scene == null or not scene.can_instantiate() or ctx == null or ctx.tick < 0:
		return null
	if not is_instance_valid(ctx.spawn_parent) or not ctx.spawn_parent.is_inside_tree():
		return null
	if not Game.is_server_or_offline(ctx.spawn_parent.multiplayer):
		return null
	if not ctx.spawn_transform.is_finite():
		return null
	var instance: Node = scene.instantiate()
	if not instance is Deployable:
		instance.free()
		return null
	var object: Deployable = instance as Deployable
	object.source_id = ctx.source_id
	object.owner_id = ctx.owner_id if ctx.owner_id > 0 else ctx.source_id
	object.team_id = ctx.team_id
	object.squad_id = ctx.squad_id
	object.spawn_tick = ctx.tick
	object.transform = ctx.spawn_parent.global_transform.affine_inverse() * ctx.spawn_transform
	ctx.spawn_parent.add_child(object, true)
	object.deployed.emit(ctx.tick)
	return object


func despawn() -> bool:
	if _despawned or not is_inside_tree() or not Game.is_server_or_offline(multiplayer):
		return false
	_despawned = true
	despawned.emit()
	queue_free()
	return true
