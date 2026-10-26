# Только представление: модель относительно камеры и 2D-оптика локального игрока.
class_name WeaponAdsView
extends Node3D

const FALLBACK_MODEL: PackedScene = preload("res://src/weapons/temporary_viewmodel.tscn")

var model: Node3D
var overlay: ScopeOverlay

var _weapon: Weapon
var _local: bool = false
var _geometry: Array[GeometryInstance3D] = []


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
	_rebuild()


func _rebuild() -> void:
	if is_instance_valid(model):
		remove_child(model)
		model.queue_free()
	model = null
	_geometry.clear()
	if _weapon != null and _weapon.data != null and _local:
		var scene: PackedScene = _weapon.data.viewmodel_scene
		model = (scene if scene != null else FALLBACK_MODEL).instantiate() as Node3D
		if model != null:
			add_child(model)
			_cache_geometry(model)
	apply_ads(0.0)


func _cache_geometry(node: Node) -> void:
	if node is GeometryInstance3D:
		_geometry.append(node as GeometryInstance3D)
	for child: Node in node.get_children():
		_cache_geometry(child)


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
