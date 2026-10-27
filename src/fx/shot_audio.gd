# Общие 32 пространственных голоса; новый звук вытесняет самый старый.
class_name ShotAudio
extends Node

const CAPACITY: int = 32

var pool: ObjectPool
var _config: ShotFxConfig


func setup(config: ShotFxConfig) -> void:
	_config = config
	pool = ObjectPool.new()
	add_child(pool)
	pool.prewarm(CAPACITY, _create_voice)


func _create_voice() -> AudioStreamPlayer3D:
	var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	voice.max_distance = _config.audio_distance
	voice.unit_size = _config.audio_unit_size
	voice.volume_db = _config.audio_volume_db
	return voice


func play_at(stream: AudioStream, point: Vector3) -> void:
	if stream == null:
		return
	var voice: AudioStreamPlayer3D = pool.acquire() as AudioStreamPlayer3D
	voice.stop()
	voice.stream = stream
	voice.global_position = point
	voice.play()


static func whiz_point(from: Vector3, to: Vector3, ear: Vector3,
		config: ShotFxConfig) -> Vector3:
	var segment: Vector3 = to - from
	var length_squared: float = segment.length_squared()
	if length_squared <= 0.0:
		return Vector3.INF
	var t: float = (ear - from).dot(segment) / length_squared
	if t <= 0.0 or t >= 1.0:
		return Vector3.INF
	var point: Vector3 = from + segment * t
	var distance: float = point.distance_to(ear)
	if distance < config.whiz_min_distance or distance > config.whiz_radius:
		return Vector3.INF
	return point
