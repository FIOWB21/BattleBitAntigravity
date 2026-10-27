# Прогретые модель/луч и шкала тепла. Здоровье и ввод представление не меняет.
class_name RepairToolView
extends Node3D

const UP_ALIGNMENT_LIMIT: float = 0.99

var _canvas: CanvasLayer
var _bar: ProgressBar
var _label: Label
var _beam: MeshInstance3D
var _working: bool = false


func setup(tool: RepairTool) -> void:
	var model: Node3D = load("res://src/gadgets/scenes/repair_tool_model.tscn").instantiate() as Node3D
	add_child(model)
	_beam = model.get_node("Beam") as MeshInstance3D
	_beam.top_level = true
	_canvas = CanvasLayer.new()
	_canvas.layer = 10
	add_child(_canvas)
	_bar = ProgressBar.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.position = Vector2(-120.0, -90.0)
	_bar.size = Vector2(240.0, 20.0)
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_canvas.add_child(_bar)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_label.position = Vector2(-120.0, -120.0)
	_label.size = Vector2(240.0, 25.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_canvas.add_child(_label)
	tool.presentation_changed.connect(_on_presentation_changed)
	set_active(false)


func set_active(active: bool) -> void:
	visible = active
	_canvas.visible = active
	_beam.visible = active and _working


func _on_presentation_changed(working: bool, point: Vector3, heat: float, locked: bool) -> void:
	_bar.value = heat
	_label.text = "OVERHEATED — COOLING" if locked else "REPAIR TOOL — HEAT"
	_working = working
	_beam.visible = visible and working
	if not working:
		return
	var origin: Vector3 = global_transform * Vector3(0.3, -0.25, -0.75)
	var direction: Vector3 = point - origin
	if direction.length_squared() <= 0.000001:
		_beam.visible = false
		return
	var up: Vector3 = Vector3.FORWARD if absf(direction.normalized().dot(Vector3.UP)) > UP_ALIGNMENT_LIMIT else Vector3.UP
	_beam.global_transform = Transform3D(Basis.looking_at(direction.normalized(), up), origin + direction * 0.5)
	_beam.scale.z = direction.length()
