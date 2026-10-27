# Кольцо отверстий: ровно 256 Decal, без создания и удаления при попадании.
class_name ShotDecals
extends Node

const CAPACITY: int = 256

var pool: ObjectPool
var _config: ShotFxConfig
var _texture: Texture2D


func setup(config: ShotFxConfig, texture: Texture2D) -> void:
	_config = config
	_texture = texture
	pool = ObjectPool.new()
	add_child(pool)
	pool.prewarm(CAPACITY, _create_decal)


func _create_decal() -> Decal:
	var decal: Decal = Decal.new()
	decal.texture_albedo = _texture
	decal.size = _config.decal_size
	decal.modulate = _config.decal_color
	decal.normal_fade = 0.5
	decal.visible = false
	return decal


func stamp(point: Vector3, normal: Vector3, surface: ShotSurface.Type) -> void:
	if not ShotSurface.accepts_decal(surface):
		return
	var decal: Decal = pool.acquire() as Decal
	decal.global_transform = Transform3D(ShotSurface.normal_basis(normal), point)
	decal.visible = true
