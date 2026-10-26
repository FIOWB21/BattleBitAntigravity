# Связь серверного fired с трассировкой; поза прицеливания поступает из симуляции.
class_name WeaponHitscan
extends Node3D

signal shot_traced(tick: int, pellet: int, direction: Vector3, hit: HitResult)
signal damage_applied(event: DamageEvent)

var _weapon: Weapon = null
var _attacker: int = 0
var _exclude: Array[RID] = []
var _aim: Transform3D = Transform3D.IDENTITY
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(weapon: Weapon, attacker: int, exclude: Array[RID]) -> void:
	if _weapon != null and _weapon.fired.is_connected(_on_fired):
		_weapon.fired.disconnect(_on_fired)
	_weapon = weapon
	_attacker = attacker
	_exclude = exclude.duplicate()
	if _weapon != null:
		_weapon.fired.connect(_on_fired)


func simulate(inp: PlayerInput, aim: Transform3D, blocked: bool = false) -> void:
	if _weapon == null or not is_inside_tree() or not multiplayer.is_server():
		return
	_aim = aim
	_weapon.simulate(inp, blocked)


func _on_fired(tick: int) -> void:
	if not is_inside_tree() or not multiplayer.is_server() or _weapon == null:
		return
	var data: WeaponData = _weapon.data
	if data == null or data.hitscan_range <= 0.0:
		return
	_rng.seed = hash(Vector2i(_attacker, tick))
	for pellet: int in range(maxi(data.pellets, 1)):
		var direction: Vector3 = _spread_direction(_aim.basis, data.spread_hip_deg)
		var hit: HitResult = HitscanQuery.cast(_aim.origin,
			_aim.origin + direction * data.hitscan_range, _exclude,
			get_world_3d().direct_space_state)
		_apply_hit(data, hit)
		shot_traced.emit(tick, pellet, direction, hit)


func _spread_direction(aim_basis: Basis, spread_deg: float) -> Vector3:
	var angle: float = deg_to_rad(clampf(spread_deg, 0.0, 90.0))
	var cos_theta: float = lerpf(1.0, cos(angle), _rng.randf())
	var sin_theta: float = sqrt(maxf(0.0, 1.0 - cos_theta * cos_theta))
	var azimuth: float = _rng.randf() * TAU
	var local: Vector3 = Vector3(cos(azimuth) * sin_theta,
		sin(azimuth) * sin_theta, -cos_theta)
	return (aim_basis * local).normalized()


func _apply_hit(data: WeaponData, hit: HitResult) -> void:
	if not hit.hit or hit.health_component == null or hit.health_component.is_dead:
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
