# Процедурная 2D-оптика: прозрачная апертура, чёрная периферия и сетка.
class_name ScopeOverlay
extends Control

@export var aperture_ratio: float = 0.36
@export var reticle_gap: float = 5.0
@export var reticle_width: float = 3.0
@export var rim_width: float = 4.0
@export var segment_count: int = 128
@export var reticle_color: Color = Color(0.08, 0.08, 0.08)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * aperture_ratio
	var mask_width: float = size.length()
	draw_arc(center, radius + mask_width * 0.5, 0.0, TAU,
		segment_count, Color.BLACK, mask_width, true)
	draw_arc(center, radius, 0.0, TAU, segment_count, reticle_color, rim_width, true)
	draw_line(center + Vector2(-radius, 0.0), center + Vector2(-reticle_gap, 0.0), reticle_color, reticle_width, true)
	draw_line(center + Vector2(reticle_gap, 0.0), center + Vector2(radius, 0.0), reticle_color, reticle_width, true)
	draw_line(center + Vector2(0.0, -radius), center + Vector2(0.0, -reticle_gap), reticle_color, reticle_width, true)
	draw_line(center + Vector2(0.0, reticle_gap), center + Vector2(0.0, radius), reticle_color, reticle_width, true)
