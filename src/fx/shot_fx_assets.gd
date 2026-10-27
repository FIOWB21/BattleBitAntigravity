# Процедурные меши, текстура и PCM создаются один раз при прогреве.
class_name ShotFxAssets
extends RefCounted

const PCM_AMPLITUDE: float = 18000.0

var tracer: BoxMesh
var shell: CylinderMesh
var impacts: Array[Mesh] = []
var flash: SphereMesh
var hole: ImageTexture
var fire_sound: AudioStreamWAV
var hit_sound: AudioStreamWAV
var headshot_sound: AudioStreamWAV
var whiz_sound: AudioStreamWAV


func build(config: ShotFxConfig) -> void:
	tracer = BoxMesh.new()
	tracer.size = Vector3.ONE
	tracer.material = _material(config.tracer_color, true)
	shell = CylinderMesh.new()
	shell.top_radius = config.shell_size.x
	shell.bottom_radius = config.shell_size.x
	shell.height = config.shell_size.y
	shell.radial_segments = 6
	shell.material = _material(config.shell_color)
	flash = SphereMesh.new()
	flash.radius = config.flash_size
	flash.height = config.flash_size * 2.0
	flash.radial_segments = 8
	flash.rings = 4
	flash.material = _material(config.flash_color, true)
	_build_impacts(config)
	hole = _hole_texture(config)
	fire_sound = _sound(config, config.fire_duration, 110.0, true)
	hit_sound = _sound(config, config.hit_duration, config.hit_frequency)
	headshot_sound = _sound(config, config.hit_duration, config.headshot_frequency)
	whiz_sound = _sound(config, config.whiz_duration, config.whiz_frequency, true, true)


func _material(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = emissive
	material.emission = color if emissive else Color.BLACK
	return material


func _build_impacts(config: ShotFxConfig) -> void:
	for surface: int in range(ShotSurface.NAMES.size()):
		var mesh: PrimitiveMesh
		if surface == ShotSurface.Type.WATER:
			var ring: TorusMesh = TorusMesh.new()
			ring.inner_radius = 0.35
			ring.outer_radius = 0.5
			ring.rings = 12
			ring.ring_segments = 6
			mesh = ring
		elif surface == ShotSurface.Type.METAL or surface == ShotSurface.Type.WOOD:
			mesh = BoxMesh.new()
		else:
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 8
			sphere.rings = 4
			mesh = sphere
		mesh.material = _material(config.impact_colors[surface], surface == ShotSurface.Type.METAL)
		impacts.append(mesh)


func _hole_texture(config: ShotFxConfig) -> ImageTexture:
	var size: int = maxi(config.decal_texture_size, 4)
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y: int in range(size):
		for x: int in range(size):
			var p: Vector2 = (Vector2(x, y) + Vector2.ONE * 0.5) / size * 2.0 - Vector2.ONE
			var radius: float = p.length() * (1.0 + 0.08 * sin(p.angle() * 11.0))
			var alpha: float = 1.0 - smoothstep(0.55, 0.95, radius)
			var shade: float = lerpf(0.04, 0.4, smoothstep(0.2, 0.65, radius))
			image.set_pixel(x, y, Color(shade, shade, shade, alpha))
	return ImageTexture.create_from_image(image)


func _sound(config: ShotFxConfig, duration: float, frequency: float,
		noise: bool = false, whiz: bool = false) -> AudioStreamWAV:
	var frames: int = maxi(1, roundi(duration * config.sample_rate))
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(frames * 2)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 29
	for frame: int in range(frames):
		var t: float = float(frame) / frames
		var envelope: float = sin(PI * t) if whiz else pow(1.0 - t, 4.0)
		var tone: float = sin(TAU * frequency * (1.0 - t * 0.35) * frame / config.sample_rate)
		var sample: float = lerpf(tone, rng.randf_range(-1.0, 1.0), 0.7) if noise else tone
		pcm.encode_s16(frame * 2, roundi(sample * envelope * PCM_AMPLITUDE))
	var sound: AudioStreamWAV = AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = config.sample_rate
	sound.data = pcm
	return sound
