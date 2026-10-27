# Пул Label на HUD: видимость зависит от команды/срока, стены не опрашиваются.
class_name SpotMarkers
extends CanvasLayer

var labels: Array[Label] = []
var _registry: SpotRegistry
var _viewer: CombatAffiliation
var _camera: Camera3D


func setup(registry: SpotRegistry, viewer: CombatAffiliation, camera: Camera3D) -> void:
	_registry = registry
	_viewer = viewer
	_camera = camera
	layer = 11
	for mark: SpotMark in registry.marks:
		var label: Label = Label.new()
		label.text = "▼ SPOTTED"
		label.modulate = Color(1.0, 0.7, 0.15)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.visible = false
		add_child(label)
		labels.append(label)


func _process(_delta: float) -> void:
	update_markers()


func update_markers() -> void:
	for index: int in range(labels.size()):
		var mark: SpotMark = _registry.marks[index]
		var label: Label = labels[index]
		label.visible = _viewer.is_alive() and mark.is_visible_to(_viewer.team_id)
		if not label.visible:
			continue
		var point: Vector3 = mark.target.actor.global_position + _registry.data.marker_offset
		label.visible = not _camera.is_position_behind(point)
		if label.visible:
			label.position = _camera.unproject_position(point) - label.size * 0.5
