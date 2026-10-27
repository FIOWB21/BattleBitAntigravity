# Подтверждённое попадание: четыре штриха без Tween/Timer и временных узлов.
class_name HitMarker
extends Control

var config: ShotFxConfig = preload("res://src/fx/default_shot_fx.tres")
var remaining: float = 0.0
var headshot: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(false)


func confirm(is_headshot: bool) -> void:
	headshot = is_headshot
	remaining = config.hit_marker_duration
	visible = true
	set_process(true)
	queue_redraw()


func advance(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)
	if remaining == 0.0:
		visible = false
		set_process(false)


func _process(delta: float) -> void:
	advance(delta)


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var color: Color = config.headshot_color if headshot else Color.WHITE
	for corner: int in range(4):
		var direction: Vector2 = Vector2(1.0 if corner & 1 else -1.0, 1.0 if corner & 2 else -1.0)
		draw_line(center + direction * config.hit_marker_inner,
			center + direction * config.hit_marker_outer, color, config.hit_marker_width, true)
