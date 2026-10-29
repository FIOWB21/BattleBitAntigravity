# Cached world models consume public snapshots, never the remote Weapon state.
class_name WorldWeaponView
extends Node3D

const FALLBACK: PackedScene = preload("res://src/weapons/temporary_viewmodel.tscn")

@export var config: WorldWeaponConfig = preload("res://src/player/default_world_weapon.tres")

var weapon_id: int = 0
var is_reloading: bool = false
var is_aiming: bool = false
var is_firing: bool = false
var model: Node3D
var _models: Dictionary[int, Node3D] = {}
var _sounds: Dictionary[int, AudioStream] = {}
var _reload_seconds: float = 0.0
var _fire_remaining: float = 0.0


func setup(actor: Player) -> void:
	position = Vector3.UP * actor.movement_config.head_height_for(actor.stance)
	visible = false
	for slot: int in range(1, Loadout.SLOT_COUNT + 1):
		var weapon: Weapon = actor.inventory.weapon_at(slot)
		if weapon != null:
			_cache(weapon.data)
	set_process(false)


func _cache(data: WeaponData) -> void:
	var id: int = data.id.hash() & SnapshotCodec.UINT_MAX
	if _models.has(id):
		return
	var scene: PackedScene = data.worldmodel_scene if data.worldmodel_scene != null else FALLBACK
	var cached: Node3D = scene.instantiate() as Node3D
	add_child(cached)
	cached.visible = false
	cached.position = config.held_offset
	if data.worldmodel_scene == null and data.category == WeaponData.Category.PISTOL:
		cached.scale = config.pistol_scale
	_models[id] = cached
	_sounds[id] = data.fire_sound


func has_weapon(id: int) -> bool:
	return _models.has(id)


func fire_sound(id: int) -> AudioStream:
	return _sounds.get(id)


func apply_snapshot(state: PlayerSnapshot, head_height: float) -> void:
	var dead: bool = (state.flags & (PlayerSnapshot.DEAD | PlayerSnapshot.DOWNED)) != 0
	if state.weapon_id != weapon_id:
		reset()
		weapon_id = state.weapon_id
		model = _models.get(weapon_id)
	is_aiming = (state.flags & PlayerSnapshot.AIMING) != 0
	var reloading: bool = (state.flags & PlayerSnapshot.RELOADING) != 0 and not dead
	if reloading != is_reloading:
		_reload_seconds = 0.0
	is_reloading = reloading
	visible = model != null and not dead
	if model != null:
		model.visible = visible
	position = Vector3.UP * head_height
	rotation = Vector3(state.pitch, 0.0, 0.0)
	_apply_pose()


func advance(delta: float) -> void:
	_fire_remaining = maxf(0.0, _fire_remaining - delta)
	is_firing = _fire_remaining > 0.0
	if is_reloading:
		_reload_seconds += delta
	_apply_pose()


func _apply_pose() -> void:
	if model == null:
		return
	var weight: float = 0.0
	if is_reloading:
		weight = sin(fmod(_reload_seconds / config.reload_cycle_seconds, 1.0) * PI)
	model.position = (config.aimed_offset if is_aiming else config.held_offset) + config.reload_offset * weight
	model.rotation = config.reload_rotation * weight


func shot_presented() -> void:
	_fire_remaining = config.firing_seconds
	is_firing = true


func muzzle_pose(id: int = 0) -> Transform3D:
	var source: Node3D = model if id == 0 else _models.get(id)
	if source != null:
		return source.global_transform * Transform3D(Basis.IDENTITY, config.muzzle_offset)
	return global_transform


func reset() -> void:
	visible = false
	if model != null:
		model.visible = false
	model = null
	weapon_id = 0
	is_reloading = false
	is_aiming = false
	is_firing = false
	_reload_seconds = 0.0
	_fire_remaining = 0.0
