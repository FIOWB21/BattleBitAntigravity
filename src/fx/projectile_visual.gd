# Прогретый визуал взрыва/дыма и голос звука, без игровой коллизии.
class_name ProjectileVisual
extends Node3D

var mesh: MeshInstance3D
var material: StandardMaterial3D
var audio: AudioStreamPlayer3D
var profile: ProjectileData
var age: float = 0.0
var active: bool = false
var _config: ProjectileFxConfig


func _exit_tree() -> void:
	audio.stop()
	audio.stream = null


func setup(config: ProjectileFxConfig, blast_sound: AudioStreamWAV) -> void:
	_config = config
	mesh = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	sphere.material = material
	mesh.mesh = sphere
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	audio = AudioStreamPlayer3D.new()
	audio.stream = blast_sound
	audio.volume_db = config.blast_volume_db
	add_child(audio)
	visible = false


func present(data: ProjectileData, point: Vector3) -> void:
	profile = data
	global_position = point
	age = 0.0
	active = true
	visible = true
	audio.stop()
	if data.kind != ProjectileData.Kind.SMOKE:
		audio.play()
	advance(0.0)


func advance(delta: float) -> void:
	if not active:
		return
	age += maxf(delta, 0.0)
	if age >= profile.effect_duration:
		active = false
		visible = false
		return
	var fraction: float = age / profile.effect_duration
	var opacity: float = _config.blast_opacity * (1.0 - fraction)
	var extent: float = lerpf(_config.projectile_radius, profile.radius, fraction)
	if profile.kind == ProjectileData.Kind.SMOKE:
		extent = profile.radius * clampf(age / _config.smoke_growth_time, 0.01, 1.0)
		opacity = _config.smoke_opacity * clampf(
			(profile.effect_duration - age) / _config.smoke_fade_time, 0.0, 1.0)
	mesh.scale = Vector3.ONE * extent
	material.albedo_color = Color(profile.color, opacity)
