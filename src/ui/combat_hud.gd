# Events drive UI; preallocated controls expire without creating nodes in a frame.
class_name CombatHUD
extends Control

@export var hit_seconds: float = 0.35
@export var damage_seconds: float = 1.0
@export var feed_seconds: float = 10.0

var feed: KillFeed = KillFeed.new()
var hit_label: Label
var damage_label: Label
var feed_labels: Array[Label] = []
var _remaining: PackedFloat64Array = PackedFloat64Array()
var _camera: Camera3D
var _hit_remaining: float = 0.0
var _damage_remaining: float = 0.0
var _direction: Vector3 = Vector3.ZERO


func setup(camera: Camera3D) -> void:
	_camera = camera
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_label = _label(Vector2(-90, 28), Vector2(180, 36), Control.PRESET_CENTER)
	hit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	damage_label = _label(Vector2(-70, -115), Vector2(140, 36), Control.PRESET_CENTER)
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	damage_label.modulate = Color(1.0, 0.25, 0.2)
	_remaining.resize(feed.capacity)
	for index: int in range(feed.capacity):
		var label: Label = _label(Vector2(-510, 35 + index * 30), Vector2(490, 28), Control.PRESET_TOP_RIGHT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		feed_labels.append(label)
	Events.hit_confirmed.connect(_hit)
	Events.damage_indicated.connect(_damage)
	Events.player_died.connect(_death)
	advance(0.0)


func _label(offset: Vector2, dimensions: Vector2, preset: int) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.set_anchors_and_offsets_preset(preset)
	label.offset_left = offset.x
	label.offset_top = offset.y
	label.offset_right = offset.x + dimensions.x
	label.offset_bottom = offset.y + dimensions.y
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _hit(zone: int, killed: bool) -> void:
	hit_label.text = "KILL CONFIRMED" if killed else ("HEAD HIT" if zone == HitboxZone.HEAD else "HIT")
	hit_label.modulate = Color(1.0, 0.3, 0.2) if killed else Color.WHITE
	_hit_remaining = hit_seconds
	hit_label.visible = true


func _damage(direction: Vector3) -> void:
	_direction = direction
	damage_label.text = "DAMAGE" if direction.is_zero_approx() else "▲"
	damage_label.rotation = 0.0
	_damage_remaining = damage_seconds
	damage_label.visible = true


func _death(victim: int, killer: int, weapon: StringName, headshot: bool) -> void:
	var full: bool = feed.lines.size() == feed.capacity
	feed.record(_nickname(victim), _nickname(killer), weapon, headshot)
	if full:
		for index: int in range(feed.capacity - 1):
			_remaining[index] = _remaining[index + 1]
	_remaining[mini(feed.lines.size(), feed.capacity) - 1] = feed_seconds
	for index: int in range(feed.lines.size()):
		feed_labels[index].text = feed.lines[index]
		feed_labels[index].visible = true


func _nickname(id: int) -> String:
	return Net.nicknames.get(id, "Environment" if id == 0 else str(id))


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	_hit_remaining = maxf(0.0, _hit_remaining - delta)
	_damage_remaining = maxf(0.0, _damage_remaining - delta)
	hit_label.visible = _hit_remaining > 0.0
	damage_label.visible = _damage_remaining > 0.0
	if damage_label.visible and is_instance_valid(_camera) and not _direction.is_zero_approx():
		var local: Vector3 = _camera.global_basis.inverse() * _direction
		damage_label.rotation = atan2(local.x, -local.z)
		damage_label.pivot_offset = damage_label.size * 0.5
	for index: int in range(feed.capacity):
		_remaining[index] = maxf(0.0, _remaining[index] - delta)
		feed_labels[index].visible = _remaining[index] > 0.0
