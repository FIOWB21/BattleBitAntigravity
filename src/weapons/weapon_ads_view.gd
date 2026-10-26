# Только представление: модель относительно камеры и 2D-оптика локального игрока.
class_name WeaponAdsView
extends Node3D

const FALLBACK_MODEL: PackedScene = preload("res://src/weapons/temporary_viewmodel.tscn")

var model: Node3D
var overlay: ScopeOverlay

var _weapon: Weapon
var _local: bool = false
var _geometry: Array[GeometryInstance3D] = []
var _models: Dictionary[Weapon, Node3D] = {}
var _geometries: Dictionary[Weapon, Array] = {}


func setup(weapon: Weapon, local: bool) -> void:
	if is_instance_valid(_weapon) and _weapon.configured.is_connected(_rebuild):
		_weapon.configured.disconnect(_rebuild)
	_weapon = weapon
	_local = local
	if _weapon != null:
		_weapon.configured.connect(_rebuild)
	if overlay == null:
		var canvas: CanvasLayer = CanvasLayer.new()
		canvas.layer = 9
		add_child(canvas)
		overlay = ScopeOverlay.new()
		canvas.add_child(overlay)
	_select_model()


# Предварительная загрузка всего комплекта: смена в физическом тике не создаёт модель.
func cache_weapon(weapon: Weapon, local: bool) -> void:
	if not local or weapon == null or _models.has(weapon):
		return
	var scene: PackedScene = weapon.data.viewmodel_scene
	var cached: Node3D = (scene if scene != null else FALLBACK_MODEL).instantiate() as Node3D
	_models[weapon] = cached
	var geometry: Array[GeometryInstance3D] = []
	_geometries[weapon] = geometry
	if cached != null:
		add_child(cached)
		cached.visible = false
		_cache_geometry(cached, geometry)


func _rebuild() -> void:
	if _models.has(_weapon):
		var cached: Node3D = _models[_weapon]
		if is_instance_valid(cached):
			remove_child(cached)
			cached.queue_free()
		_models.erase(_weapon)
		_geometries.erase(_weapon)
	model = null
	_select_model()


func _select_model() -> void:
	if is_instance_valid(model):
		model.visible = false
	cache_weapon(_weapon, _local)
	model = _models.get(_weapon) as Node3D if _weapon != null and _local else null
	if model != null:
		model.visible = true
		_geometry = _geometries[_weapon]
	apply_ads(0.0)


func _cache_geometry(node: Node, geometry: Array[GeometryInstance3D]) -> void:
	if node is GeometryInstance3D:
		geometry.append(node as GeometryInstance3D)
	for child: Node in node.get_children():
		_cache_geometry(child, geometry)


func apply_ads(amount: float) -> void:
	var data: WeaponData = _weapon.data if _weapon != null else null
	visible = _local and data != null
	if data != null:
		position = data.viewmodel_hip_offset.lerp(data.viewmodel_ads_offset, amount)
		for geometry: GeometryInstance3D in _geometry:
			geometry.transparency = amount if data.scope_overlay_enabled else 0.0
	if overlay != null:
		overlay.visible = visible and data.scope_overlay_enabled and amount > 0.0
		overlay.modulate.a = amount
