# Три косметических движения без физических тел и изменения игрового мира.
class_name ShotVisual
extends MeshInstance3D

enum Kind { TRACER, SHELL, IMPACT }

var kind: Kind = Kind.TRACER
var surface: ShotSurface.Type = ShotSurface.Type.CONCRETE
var remaining: float = 0.0
var _config: ShotFxConfig
var _assets: ShotFxAssets
var _velocity: Vector3 = Vector3.ZERO
var _origin: Vector3 = Vector3.ZERO
var _direction: Vector3 = Vector3.FORWARD
var _distance: float = 0.0
var _travelled: float = 0.0
var _base_scale: Vector3 = Vector3.ONE


func setup(config: ShotFxConfig, assets: ShotFxAssets, visual_kind: Kind) -> void:
	_config = config
	_assets = assets
	kind = visual_kind
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
	mesh = assets.tracer if kind == Kind.TRACER else assets.shell
	if kind == Kind.IMPACT:
		mesh = assets.impacts[ShotSurface.Type.CONCRETE]


func play_tracer(from: Vector3, to: Vector3) -> void:
	_origin = from
	_distance = from.distance_to(to)
	_direction = from.direction_to(to)
	_travelled = 0.0
	remaining = (_distance + _config.tracer_length) / _config.tracer_speed
	visible = _distance > 0.0
	if visible:
		_update_tracer()


func play_shell(pose: Transform3D) -> void:
	global_transform = pose
	_velocity = pose.basis * _config.shell_velocity
	remaining = _config.shell_lifetime
	transparency = 0.0
	visible = true


func play_impact(point: Vector3, normal: Vector3, surface_type: ShotSurface.Type) -> void:
	surface = surface_type
	mesh = _assets.impacts[surface]
	_base_scale = _config.impact_scales[surface]
	var orientation: Basis = ShotSurface.normal_basis(normal)
	global_transform = Transform3D(orientation.scaled(_base_scale),
		point + orientation.y * _config.impact_offset)
	_velocity = orientation.y * _config.impact_speed
	remaining = _config.impact_lifetime
	transparency = 0.0
	visible = true


func advance(delta: float) -> void:
	if not visible:
		return
	remaining = maxf(0.0, remaining - delta)
	if remaining == 0.0:
		visible = false
		return
	match kind:
		Kind.TRACER:
			_travelled += _config.tracer_speed * delta
			_update_tracer()
		Kind.SHELL:
			global_position += _velocity * delta + Vector3.DOWN * _config.shell_gravity * delta * delta * 0.5
			_velocity.y -= _config.shell_gravity * delta
			rotate_object_local(Vector3.RIGHT, _config.shell_spin.x * delta)
			rotate_object_local(Vector3.UP, _config.shell_spin.y * delta)
			rotate_object_local(Vector3.BACK, _config.shell_spin.z * delta)
			transparency = 1.0 - remaining / _config.shell_lifetime
		Kind.IMPACT:
			global_position += _velocity * delta
			var fraction: float = 1.0 - remaining / _config.impact_lifetime
			scale = _base_scale * (1.0 + fraction)
			transparency = fraction


func _update_tracer() -> void:
	var start: float = minf(_travelled, _distance)
	var end: float = minf(_travelled + _config.tracer_length, _distance)
	if end <= start:
		visible = false
		return
	var helper: Vector3 = Vector3.RIGHT if absf(_direction.y) > 0.99 else Vector3.UP
	global_transform = Transform3D(Basis.looking_at(_direction, helper).scaled(
		Vector3(_config.tracer_width, _config.tracer_width, end - start)),
		_origin + _direction * ((start + end) * 0.5))
