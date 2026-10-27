# Процедурная анимация ножа; сигналы симуляции не зависят от наличия модели.
class_name MeleeView
extends Node3D

var _attack: MeleeAttack
var _weapon_view: WeaponAdsView
var _age: float = 0.0
var _playing: bool = false


func setup(attack: MeleeAttack, weapon_view: WeaponAdsView) -> void:
	_attack = attack
	_weapon_view = weapon_view
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_add_part(attack.data.blade_size, Vector3(0.0, 0.0, -attack.data.blade_size.z * 0.5), attack.data.blade_color)
	_add_part(attack.data.grip_size, Vector3(0.0, 0.0, attack.data.grip_size.z * 0.5), attack.data.grip_color)
	attack.attack_started.connect(_on_started)
	attack.attack_finished.connect(_on_finished)
	visible = false


func _add_part(size: Vector3, offset: Vector3, color: Color) -> void:
	var part: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.use_fov_override = true
	material.fov_override = _attack.data.viewmodel_fov
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = ViewmodelRig.RENDER_PRIORITY
	mesh.material = material
	part.mesh = mesh
	part.position = offset
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.ignore_occlusion_culling = true
	add_child(part)


func _on_started() -> void:
	_age = 0.0
	_playing = true
	visible = true
	advance(0.0)


func _on_finished() -> void:
	_playing = false
	visible = false
	if is_instance_valid(_weapon_view):
		_weapon_view.apply_ads(0.0)


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if not _playing or not is_finite(delta) or delta < 0.0:
		return
	_age += delta
	var data: MeleeData = _attack.data
	var contact: float = maxf(data.hit_delay, 1.0 / Engine.physics_ticks_per_second)
	if _age < contact:
		var blend: float = smoothstep(0.0, contact, _age)
		position = data.windup_offset.lerp(data.strike_offset, blend)
		rotation = data.windup_rotation.lerp(data.strike_rotation, blend)
	else:
		var blend: float = smoothstep(contact,
			maxf(data.duration, contact + 1.0 / Engine.physics_ticks_per_second), _age)
		position = data.strike_offset.lerp(data.rest_offset, blend)
		rotation = data.strike_rotation.lerp(Vector3.ZERO, blend)
	if is_instance_valid(_weapon_view):
		_weapon_view.visible = false
		if _weapon_view.overlay != null:
			_weapon_view.overlay.visible = false
