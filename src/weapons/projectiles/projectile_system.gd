# Пул игровых снарядов не вытесняет активные гранаты: при заполнении запуск отклоняется.
class_name ProjectileSystem
extends Node3D

signal launched(projectile: Projectile)
signal exploded(profile: ProjectileData, point: Vector3, attacker: int)

@export var capacity: int = 16

var projectiles: Array[Projectile] = []
var explosion: Explosion
var _cursor: int = 0


func _ready() -> void:
	top_level = true
	explosion = Explosion.new()
	add_child(explosion)
	for index: int in range(capacity):
		var projectile: Projectile = Projectile.new()
		add_child(projectile)
		projectile.detonated.connect(_on_detonated)
		projectiles.append(projectile)


func launch(profile: ProjectileData, origin: Vector3, velocity: Vector3,
		attacker: int = 0, exclude: Array[RID] = []) -> Projectile:
	if not multiplayer.is_server() or projectiles.is_empty():
		return null
	for offset: int in range(projectiles.size()):
		var index: int = (_cursor + offset) % projectiles.size()
		var projectile: Projectile = projectiles[index]
		if projectile.active:
			continue
		if not projectile.launch(profile, origin, velocity, attacker, exclude):
			return null
		_cursor = (index + 1) % projectiles.size()
		launched.emit(projectile)
		return projectile
	return null


func _physics_process(delta: float) -> void:
	advance(delta)


func has_capacity() -> bool:
	for projectile: Projectile in projectiles:
		if not projectile.active:
			return true
	return false


func advance(delta: float) -> void:
	for projectile: Projectile in projectiles:
		projectile.simulate(delta)


func _on_detonated(projectile: Projectile) -> void:
	var profile: ProjectileData = projectile.data
	var point: Vector3 = projectile.global_position
	if profile.kind == ProjectileData.Kind.FRAG or profile.kind == ProjectileData.Kind.ROCKET:
		explosion.apply(profile, point, projectile.attacker)
	exploded.emit(profile, point, projectile.attacker)
