# Команда броска из PlayerInput; сервер назначает профиль, скорость и источник.
class_name PlayerProjectiles
extends Node

signal grenades_changed(count: int, capacity: int)

@export var profile: ProjectileData = preload("res://src/weapons/projectiles/frag.tres")
@export var stock: GrenadeStockConfig = preload("res://src/player/default_grenade_stock.tres")

var grenades: int = 0
var stock_view: GrenadeStockView
var system: ProjectileSystem
var effects: ProjectileEffects
var _player: Player
var _exclude: Array[RID] = []
var _last_tick: int = -1
var _next_tick: int = 0


func setup(player: Player) -> void:
	_player = player
	grenades = stock.initial_count if stock != null and stock.is_valid() else 0
	_exclude = player.get_hitscan_exclude_rids().duplicate()
	if not _exclude.has(player.get_rid()):
		_exclude.append(player.get_rid())
	system = ProjectileSystem.new()
	system.name = "ProjectileSystem"
	add_child(system)
	if not Game.is_dedicated:
		effects = ProjectileEffects.new()
		add_child(effects)
		effects.setup(system, player.camera if player.is_local_player else get_viewport().get_camera_3d())
		if player.is_local_player:
			stock_view = GrenadeStockView.new()
			add_child(stock_view)
			stock_view.setup(self)


func simulate(inp: PlayerInput) -> void:
	if not multiplayer.is_server() or inp.tick <= _last_tick:
		return
	_last_tick = inp.tick
	if not inp.throw_grenade or inp.tick < _next_tick or profile == null or grenades <= 0:
		return
	if _player.health_component is HealthComponent and _player.health_component.is_dead:
		return
	var pitch: float = clampf(inp.pitch, -LocalInputReader.MAX_PITCH_RAD, LocalInputReader.MAX_PITCH_RAD)
	var direction: Vector3 = -Basis.from_euler(Vector3(pitch, inp.yaw, 0.0)).z
	var velocity: Vector3 = direction * profile.speed + Vector3.UP * profile.upward_speed
	var projectile: Projectile = system.launch(profile, _player.head.global_position,
		velocity, _player.get_multiplayer_authority(), _exclude)
	if projectile != null:
		grenades -= 1
		grenades_changed.emit(grenades, stock.capacity)
		_next_tick = inp.tick + maxi(1, ceili(profile.throw_interval * Engine.physics_ticks_per_second))


func add_grenades(amount: int) -> int:
	if not is_inside_tree() or not Game.is_server_or_offline(multiplayer) or amount <= 0:
		return 0
	if stock == null or not stock.is_valid() or (_player.health_component as HealthComponent).is_dead:
		return 0
	var added: int = mini(amount, maxi(0, stock.capacity - grenades))
	if added > 0:
		grenades += added
		grenades_changed.emit(grenades, stock.capacity)
	return added
