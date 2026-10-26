# Трассировка луча хитскана по геометрии мира (world) и зонам хитбоксов (hitboxes).
class_name HitscanQuery
extends RefCounted

const LAYER_WORLD: int = 1 << 0
const LAYER_HITBOXES: int = 1 << 2
const DEFAULT_COLLISION_MASK: int = LAYER_WORLD | LAYER_HITBOXES

static var _ray_query: PhysicsRayQueryParameters3D = null
static var _exclude_buffer: Array[RID] = []


static func cast(
	from: Vector3,
	to: Vector3,
	exclude: Array = [],
	space_state: PhysicsDirectSpaceState3D = null
) -> HitResult:
	var result: HitResult = HitResult.new()
	var resolved_space: PhysicsDirectSpaceState3D = _resolve_space_state(space_state)
	if resolved_space == null:
		return result
	if _ray_query == null:
		_ray_query = PhysicsRayQueryParameters3D.new()
	_fill_exclude_rids(exclude)
	_ray_query.from = from
	_ray_query.to = to
	_ray_query.collision_mask = DEFAULT_COLLISION_MASK
	_ray_query.collide_with_areas = true
	_ray_query.collide_with_bodies = true
	_ray_query.exclude = _exclude_buffer
	var raw: Dictionary = resolved_space.intersect_ray(_ray_query)
	if raw.is_empty():
		return result
	_populate_result(result, raw)
	return result


static func _resolve_space_state(
	explicit_space: PhysicsDirectSpaceState3D
) -> PhysicsDirectSpaceState3D:
	if explicit_space != null:
		return explicit_space
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop as SceneTree
		if tree.root != null and tree.root.get_world_3d() != null:
			return tree.root.get_world_3d().direct_space_state
	return null


static func _fill_exclude_rids(exclude: Array) -> void:
	_exclude_buffer.clear()
	for item: Variant in exclude:
		if item is RID:
			_exclude_buffer.append(item)
		elif item is Object:
			_append_object_rids(item as Object)


static func _append_object_rids(obj: Object) -> void:
	if obj.has_method("get_hitscan_exclude_rids"):
		var rids: Array = obj.call("get_hitscan_exclude_rids")
		for rid_item: Variant in rids:
			if rid_item is RID:
				_exclude_buffer.append(rid_item)
		return
	if obj.has_method("get_exclude_rids"):
		var rids: Array = obj.call("get_exclude_rids")
		for rid_item: Variant in rids:
			if rid_item is RID:
				_exclude_buffer.append(rid_item)
		return
	if obj is CollisionObject3D:
		_exclude_buffer.append((obj as CollisionObject3D).get_rid())


static func _populate_result(result: HitResult, raw: Dictionary) -> void:
	result.hit = true
	result.position = raw.get("position", Vector3.ZERO)
	result.normal = raw.get("normal", Vector3.ZERO)
	result.collider = raw.get("collider", null)
	result.rid = raw.get("rid", RID())
	if result.collider is HitboxZone:
		var hb: HitboxZone = result.collider as HitboxZone
		result.hitbox = hb
		result.zone = hb.zone
		result.damage_mult = hb.damage_mult
		result.health_component = hb.health_component
		result.entity = hb.get_entity()
		result.target = hb.health_component if hb.health_component != null else result.entity
	else:
		result.zone = HitboxZone.NONE
		result.damage_mult = 1.0
		result.target = result.collider
		if result.collider is Node:
			result.entity = result.collider as Node
