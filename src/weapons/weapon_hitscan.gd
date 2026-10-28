# Связь серверного fired с трассировкой; поза прицеливания поступает из симуляции.
class_name WeaponHitscan
extends Node3D

signal shot_traced(tick: int, pellet: int, direction: Vector3, hit: HitResult)
signal damage_applied(event: DamageEvent)

var handling: WeaponHandling = WeaponHandling.new()
var projectiles: ProjectileSystem
var shot_origin: Vector3:
	get:
		return _aim.origin

var _weapon: Weapon = null
var _attacker: int = 0
var _exclude: Array[RID] = []
var _aim: Transform3D = Transform3D.IDENTITY
var _spread_deg: float = 0.0
var cosmetic_only: bool = false
var shot_seed: int = -1
var aim_transform: Transform3D:
	get:
		return _aim
var spread: float:
	get:
		return _spread_deg


func setup(weapon: Weapon, attacker: int, exclude: Array[RID]) -> void:
	if _weapon != null and _weapon.fired.is_connected(_on_fired):
		_weapon.fired.disconnect(_on_fired)
	if _weapon != null and _weapon.configured.is_connected(_reset_handling):
		_weapon.configured.disconnect(_reset_handling)
		_weapon.stats_changed.disconnect(_update_stats)
	_weapon = weapon
	_attacker = attacker
	_exclude = exclude.duplicate()
	if _weapon != null:
		_weapon.fired.connect(_on_fired)
		_weapon.configured.connect(_reset_handling)
		_weapon.stats_changed.connect(_update_stats)
	_reset_handling()


func simulate(inp: PlayerInput, aim: Transform3D, blocked: bool = false,
		stance: int = PlayerStance.STAND, horizontal_speed: float = 0.0,
		sprinting: bool = false, ads_amount: float = -1.0) -> void:
	if _weapon == null or not is_inside_tree() or (not multiplayer.is_server() and not cosmetic_only):
		return
	if not handling.advance(inp.tick, _weapon.ticks_per_second):
		return
	var angles: Vector3 = aim.basis.get_euler()
	_aim = Transform3D(Basis.from_euler(handling.aim_rotation(angles.x, angles.y, angles.z)), aim.origin)
	_spread_deg = handling.spread_degrees(inp.pressed(PlayerInput.BTN_AIM), stance, horizontal_speed)
	if ads_amount >= 0.0:
		_spread_deg = lerpf(handling.spread_degrees(false, stance, horizontal_speed),
			handling.spread_degrees(true, stance, horizontal_speed), clampf(ads_amount, 0.0, 1.0))
	var projectile_blocked: bool = _weapon.data != null and _weapon.data.projectile_data != null
	if projectile_blocked:
		projectile_blocked = projectiles == null or not projectiles.has_capacity()
	if cosmetic_only and not multiplayer.is_server():
		_weapon.simulate_cosmetic(inp, blocked, sprinting)
	else:
		_weapon.simulate(inp, blocked or projectile_blocked, sprinting)


func _reset_handling() -> void:
	handling.setup(_weapon.data if _weapon != null else null)


func _update_stats() -> void:
	handling.update_data(_weapon.data)


func _on_fired(tick: int) -> void:
	if not is_inside_tree() or _weapon == null or (not multiplayer.is_server() and not cosmetic_only):
		return
	var data: WeaponData = _weapon.data
	if data == null:
		return
	if data.projectile_data != null and multiplayer.is_server():
		_launch_projectile(tick, data.projectile_data)
		handling.apply_shot(tick, _attacker)
		return
	if data.hitscan_range <= 0.0:
		return
	for pellet: int in range(maxi(data.pellets, 1)):
		var direction: Vector3 = handling.spread_direction(_aim.basis, _spread_deg,
			shot_seed if shot_seed >= 0 else tick, _attacker, pellet)
		var hit: HitResult = HitscanQuery.cast(_aim.origin,
			_aim.origin + direction * data.hitscan_range, _exclude,
			get_world_3d().direct_space_state)
		if multiplayer.is_server():
			_apply_hit(data, hit)
		shot_traced.emit(tick, pellet, direction, hit)
	handling.apply_shot(tick, _attacker)


func _launch_projectile(tick: int, profile: ProjectileData) -> void:
	if projectiles == null:
		return
	var direction: Vector3 = handling.spread_direction(_aim.basis, _spread_deg,
		shot_seed if shot_seed >= 0 else tick, _attacker, 0)
	projectiles.launch(profile, _aim.origin,
		direction * profile.speed + Vector3.UP * profile.upward_speed, _attacker, _exclude)


func _apply_hit(data: WeaponData, hit: HitResult) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	if not hit.hit or hit.health_component == null or not hit.health_component.can_receive_damage():
		return
	var event: DamageEvent = DamageEvent.new()
	event.attacker = _attacker
	event.target = hit.entity
	event.zone = hit.zone
	event.distance = _aim.origin.distance_to(hit.point)
	event.damage = DamageCalc.compute(data, event.distance, hit.hitbox)
	event.weapon = data.id
	event.point = hit.point
	if event.damage <= 0.0:
		return
	hit.health_component.apply_damage(event.damage, event.attacker, event.zone)
	damage_applied.emit(event)


func fire_requested(tick: int, seed: int, aim: Transform3D, spread_deg: float) -> bool:
	if not is_inside_tree() or not multiplayer.is_server() or _weapon == null:
		return false
	if _weapon.data.projectile_data != null and (projectiles == null or not projectiles.has_capacity()):
		return false
	_aim = aim
	_spread_deg = spread_deg
	shot_seed = seed
	var accepted: bool = _weapon.fire_requested(tick)
	shot_seed = -1
	return accepted
