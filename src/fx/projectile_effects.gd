# Косметика слушает события; отдельный вход present позволяет будущую доставку с сервера.
class_name ProjectileEffects
extends Node3D

const PCM_AMPLITUDE: float = 12000.0
const SOUND_DECAY_FRACTION: float = 0.2

@export var config: ProjectileFxConfig = preload("res://src/fx/default_projectile_fx.tres")

var pool: ObjectPool
var listener: Camera3D
var flash: ColorRect
var ringing: AudioStreamPlayer
var sensory_remaining: float = 0.0
var sensory_strength: float = 0.0
var _sensory_duration: float = 0.0
var _source: ProjectileSystem
var _models: Array[MeshInstance3D] = []
var _blast_sound: AudioStreamWAV


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _exit_tree() -> void:
	if is_instance_valid(ringing):
		ringing.stop()
		ringing.stream = null


func setup(source: ProjectileSystem, camera: Camera3D) -> void:
	_source = source
	listener = camera
	_blast_sound = _sound(config.blast_tone, config.blast_duration, false)
	pool = ObjectPool.new()
	add_child(pool)
	pool.prewarm(config.effect_capacity, _create_visual)
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = config.projectile_radius
	sphere.height = config.projectile_radius * 2.0
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = config.projectile_color
	sphere.material = material
	for projectile: Projectile in source.projectiles:
		var model: MeshInstance3D = MeshInstance3D.new()
		model.mesh = sphere
		projectile.add_child(model)
		model.visible = false
		_models.append(model)
	_setup_senses()
	source.exploded.connect(present)


func _create_visual() -> Node:
	var visual: ProjectileVisual = ProjectileVisual.new()
	visual.setup(config, _blast_sound)
	return visual


func _setup_senses() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	flash = ColorRect.new()
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.visible = false
	layer.add_child(flash)
	ringing = AudioStreamPlayer.new()
	ringing.stream = _sound(config.ring_frequency, 1.0, true)
	ringing.volume_db = config.ring_volume_db
	add_child(ringing)


func present(profile: ProjectileData, point: Vector3, _attacker: int = 0) -> void:
	var visual: ProjectileVisual = pool.acquire() as ProjectileVisual
	if visual != null:
		visual.present(profile, point)
	if not is_instance_valid(listener) or profile.kind == ProjectileData.Kind.SMOKE or profile.radius <= 0.0:
		return
	var offset: Vector3 = point - listener.global_position
	if not _source.explosion.has_line_of_sight(point, listener.global_position, profile.occlusion_mask):
		return
	var strength: float = clampf(1.0 - offset.length() / profile.radius, 0.0, 1.0)
	if profile.kind == ProjectileData.Kind.FLASH and not offset.is_zero_approx():
		strength *= clampf((-listener.global_basis.z).dot(offset.normalized()), 0.0, 1.0)
	if strength <= 0.0 or profile.sensory_duration <= 0.0:
		return
	sensory_remaining = maxf(sensory_remaining, profile.sensory_duration * strength)
	_sensory_duration = sensory_remaining
	if profile.kind != ProjectileData.Kind.FLASH:
		strength *= config.stun_opacity
	if strength >= sensory_strength:
		flash.color = Color.WHITE if profile.kind == ProjectileData.Kind.FLASH else config.stun_color
	sensory_strength = maxf(sensory_strength, strength)
	ringing.play()
	advance(0.0)


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	for index: int in range(_models.size()):
		_models[index].visible = _source.projectiles[index].active
	for item: Node in pool.items:
		(item as ProjectileVisual).advance(delta)
	sensory_remaining = maxf(sensory_remaining - maxf(delta, 0.0), 0.0)
	flash.visible = sensory_remaining > 0.0
	if not flash.visible:
		sensory_strength = 0.0
		ringing.stop()
		return
	var fade: float = sensory_remaining / _sensory_duration
	flash.color.a = sensory_strength * fade
	ringing.volume_db = config.ring_volume_db + linear_to_db(maxf(fade, 0.001))


func _sound(frequency: float, duration: float, looped: bool) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.mix_rate = config.sample_rate
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	var count: int = ceili(config.sample_rate * duration)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	for index: int in range(count):
		var time: float = float(index) / config.sample_rate
		var envelope: float = 1.0 if looped else exp(-time / (duration * SOUND_DECAY_FRACTION))
		var value: float = sin(TAU * frequency * time) * envelope * PCM_AMPLITUDE
		bytes.encode_s16(index * 2, int(value))
	stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = count
	return stream
