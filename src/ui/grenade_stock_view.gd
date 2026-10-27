# Косметический счётчик подписывается на события серверного запаса.
class_name GrenadeStockView
extends CanvasLayer

var _label: Label


func setup(component: PlayerProjectiles) -> void:
	layer = 10
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_label.position = Vector2(-200.0, -95.0)
	_label.size = Vector2(180.0, 30.0)
	add_child(_label)
	component.grenades_changed.connect(_on_changed)
	_on_changed(component.grenades, component.stock.capacity if component.stock != null else 0)


func _on_changed(count: int, capacity: int) -> void:
	_label.text = "GRENADES  %d / %d" % [count, capacity]
