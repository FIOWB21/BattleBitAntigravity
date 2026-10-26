# Только представление: короткий собственный PCM-щелчок создаётся один раз.
class_name WeaponDryFire
extends AudioStreamPlayer

const PEAK_AMPLITUDE: float = 12000.0

@export var sample_rate: int = 22050
@export var duration: float = 0.035
@export var frequency: float = 1800.0


func _ready() -> void:
	if stream == null:
		stream = _make_click()
	var weapon: Weapon = get_parent() as Weapon
	if weapon != null:
		weapon.dry_fired.connect(_on_dry_fired)


func _on_dry_fired(_tick: int) -> void:
	play()


func _make_click() -> AudioStreamWAV:
	var rate: int = maxi(sample_rate, 1)
	var frames: int = maxi(1, roundi(duration * rate))
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(frames * 2)
	for frame: int in range(frames):
		var envelope: float = 1.0 - float(frame) / frames
		var sample: float = sin(TAU * frequency * frame / rate) * envelope * envelope
		pcm.encode_s16(frame * 2, roundi(sample * PEAK_AMPLITUDE))
	var click: AudioStreamWAV = AudioStreamWAV.new()
	click.format = AudioStreamWAV.FORMAT_16_BITS
	click.mix_rate = rate
	click.data = pcm
	return click
