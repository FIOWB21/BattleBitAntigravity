# Отдельный узел представления под камерой. Все модели прогреты до кадрового цикла.
class_name ViewmodelRig
extends Node3D

const DEFAULT_CONFIG: ViewmodelConfig = preload("res://src/weapons/data/default_viewmodel.tres")
const RENDER_PRIORITY: int = 127

var motion: ViewmodelMotion = ViewmodelMotion.new()
var config: ViewmodelConfig = DEFAULT_CONFIG
var _weapon: Weapon


func bind_weapon(weapon: Weapon) -> void:
	_disconnect_weapon()
	_weapon = weapon
	motion.reset()
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	if weapon == null:
		return
	config = weapon.data.viewmodel_config if weapon.data.viewmodel_config != null else DEFAULT_CONFIG
	weapon.fired.connect(_on_fired)
	weapon.reload_started.connect(_on_reload_started)
	weapon.reload_finished.connect(_on_reload_stopped)
	weapon.reload_cancelled.connect(_on_reload_stopped)
	if weapon.state == Weapon.State.RELOADING:
		_on_reload_started()


func _disconnect_weapon() -> void:
	if not is_instance_valid(_weapon):
		return
	_weapon.fired.disconnect(_on_fired)
	_weapon.reload_started.disconnect(_on_reload_started)
	_weapon.reload_finished.disconnect(_on_reload_stopped)
	_weapon.reload_cancelled.disconnect(_on_reload_stopped)


func advance(delta: float, speed: float, grounded: bool, sprinting: bool) -> void:
	if _weapon == null:
		return
	motion.advance(config, delta, speed, grounded, sprinting)
	position = motion.offset.value
	rotation = motion.angles.value


func prepare_geometry(geometry: GeometryInstance3D, settings: ViewmodelConfig) -> void:
	geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	geometry.ignore_occlusion_culling = true
	if not geometry is MeshInstance3D:
		return
	var instance: MeshInstance3D = geometry as MeshInstance3D
	if instance.mesh == null:
		return
	instance.mesh = instance.mesh.duplicate() as Mesh
	for surface: int in range(instance.mesh.get_surface_count()):
		var source: Material = instance.get_active_material(surface)
		var material: BaseMaterial3D = source.duplicate() as BaseMaterial3D if source is BaseMaterial3D else StandardMaterial3D.new()
		material.use_fov_override = true
		material.fov_override = settings.fov
		material.no_depth_test = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.render_priority = RENDER_PRIORITY
		instance.mesh.surface_set_material(surface, material)


func _on_fired(_tick: int) -> void:
	motion.kick(config)


func _on_reload_started() -> void:
	var duration: float = _weapon.data.reload_empty_time if _weapon.ammo_in_mag == 0 else _weapon.data.reload_time
	motion.start_reload(duration)


func _on_reload_stopped() -> void:
	motion.stop_reload()
