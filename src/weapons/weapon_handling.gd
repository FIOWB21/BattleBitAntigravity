# Детерминированное состояние отдачи и разброса; без дерева сцены и рендера.
class_name WeaponHandling
extends RefCounted

const MAX_PITCH_RAD: float = deg_to_rad(89.0)

var recoil_deg: Vector2 = Vector2.ZERO
var bloom_deg: float = 0.0

var _data: WeaponData
var _last_tick: int = -1
var _last_shot_tick: int = -1
var _shot_index: int = 0
var _ticks_per_second: int = Engine.physics_ticks_per_second
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(data: WeaponData) -> void:
	_data = data
	recoil_deg = Vector2.ZERO
	bloom_deg = 0.0
	_last_tick = -1
	_last_shot_tick = -1
	_shot_index = 0


# Разрыв тиков восстанавливает состояние за весь пропущенный интервал.
func advance(tick: int, ticks_per_second: int) -> bool:
	if _data == null or tick <= _last_tick:
		return false
	_ticks_per_second = maxi(ticks_per_second, 1)
	if _last_tick >= 0:
		var delta: float = float(tick - _last_tick) / _ticks_per_second
		bloom_deg = move_toward(bloom_deg, 0.0,
			maxf(_data.spread_recovery_deg_per_second, 0.0) * delta)
		var recovery_start: int = maxi(_last_tick, _last_shot_tick + _pause_ticks())
		var recovery_delta: float = float(maxi(tick - recovery_start, 0)) / _ticks_per_second
		recoil_deg = recoil_deg.move_toward(Vector2.ZERO,
			maxf(_data.recoil_recovery_deg_per_second, 0.0) * recovery_delta)
	_last_tick = tick
	return true


# Один импульс на fired, независимо от числа дробин. Паттерн, затем шум.
func apply_shot(tick: int, attacker: int) -> void:
	if _data == null or tick != _last_tick or tick == _last_shot_tick:
		return
	if _last_shot_tick < 0 or tick - _last_shot_tick >= _pause_ticks():
		_shot_index = 0
	var kick: Vector2 = _data.recoil_fallback_deg
	if _shot_index < _data.recoil_pattern.size():
		kick = _data.recoil_pattern[_shot_index]
	else:
		_rng.seed = hash(Vector3i(attacker, tick, -1))
		kick += Vector2(_rng.randf_range(-absf(_data.recoil_noise_deg.x), absf(_data.recoil_noise_deg.x)),
			_rng.randf_range(-absf(_data.recoil_noise_deg.y), absf(_data.recoil_noise_deg.y)))
	recoil_deg += kick
	bloom_deg = clampf(bloom_deg + maxf(_data.spread_per_shot_deg, 0.0),
		0.0, maxf(_data.spread_max_bloom_deg, 0.0))
	_last_shot_tick = tick
	_shot_index += 1


func spread_degrees(ads: bool, stance: int, horizontal_speed: float) -> float:
	if _data == null:
		return 0.0
	var base: float = _data.spread_ads_deg if ads else _data.spread_hip_deg
	var extra: float = bloom_deg + maxf(horizontal_speed, 0.0) * maxf(_data.spread_move_deg_per_mps, 0.0)
	if ads:
		extra *= maxf(_data.spread_ads_extra_mult, 0.0)
	var multiplier: float = 1.0
	if stance == PlayerStance.CROUCH:
		multiplier = _data.spread_crouch_mult
	elif stance == PlayerStance.PRONE:
		multiplier = _data.spread_prone_mult
	return clampf((maxf(base, 0.0) + extra) * maxf(multiplier, 0.0),
		0.0, clampf(_data.spread_max_deg, 0.0, 90.0))


func aim_rotation(pitch: float, yaw: float, roll: float) -> Vector3:
	return Vector3(clampf(pitch + deg_to_rad(recoil_deg.x), -MAX_PITCH_RAD, MAX_PITCH_RAD),
		yaw + deg_to_rad(recoil_deg.y), roll)


# Равномерно по телесному углу конуса; отдельный сид для каждой дробины.
func spread_direction(aim_basis: Basis, spread_deg: float, tick: int,
		attacker: int, pellet: int) -> Vector3:
	_rng.seed = hash(Vector3i(attacker, tick, pellet))
	var angle: float = deg_to_rad(clampf(spread_deg, 0.0, 90.0))
	var cos_theta: float = lerpf(1.0, cos(angle), _rng.randf())
	var sin_theta: float = sqrt(maxf(0.0, 1.0 - cos_theta * cos_theta))
	var azimuth: float = _rng.randf() * TAU
	var local: Vector3 = Vector3(cos(azimuth) * sin_theta,
		sin(azimuth) * sin_theta, -cos_theta)
	return (aim_basis * local).normalized()


func _pause_ticks() -> int:
	return maxi(1, ceili(maxf(_data.recoil_pause, 0.0) * _ticks_per_second))
