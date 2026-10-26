# ADS: детерминированный переход и отдельный покадровый переход представления.
class_name WeaponAds
extends RefCounted

const MIN_FOV: float = 1.0
const MAX_FOV: float = 179.0

var fraction: float = 0.0
var visual_fraction: float = 0.0
var target: float = 0.0

var _data: WeaponData
var _last_tick: int = -1


func setup(data: WeaponData) -> void:
	_data = data
	fraction = 0.0
	visual_fraction = 0.0
	target = 0.0
	_last_tick = -1


func simulate(inp: PlayerInput, delta: float, allowed: bool = true) -> void:
	if inp.tick <= _last_tick:
		return
	_last_tick = inp.tick
	target = 1.0 if allowed and _data != null and inp.pressed(PlayerInput.BTN_AIM) else 0.0
	fraction = _advance(fraction, delta)


func update_visuals(delta: float) -> void:
	visual_fraction = _advance(visual_fraction, delta)


func amount(visual: bool = false) -> float:
	return smoothstep(0.0, 1.0, visual_fraction if visual else fraction)


func fov(base_fov: float) -> float:
	var base: float = clampf(base_fov, MIN_FOV, MAX_FOV)
	var multiplier: float = clampf(_data.ads_fov_mult, 0.0, 1.0) if _data != null else 1.0
	var aimed: float = clampf(base * multiplier, MIN_FOV, base)
	return lerpf(base, aimed, amount(true))


# Отношение тангенсов — обратное увеличение перспективной проекции.
static func sensitivity_scale(current_fov: float, base_fov: float) -> float:
	var base: float = clampf(base_fov, MIN_FOV, MAX_FOV)
	var current: float = clampf(current_fov, MIN_FOV, base)
	return tan(deg_to_rad(current) * 0.5) / tan(deg_to_rad(base) * 0.5)


func movement_multiplier() -> float:
	if _data == null:
		return 1.0
	return maxf(_data.move_speed_mult, 0.0) * lerpf(1.0,
		clampf(_data.ads_move_speed_mult, 0.0, 1.0), amount())


func _advance(value: float, delta: float) -> float:
	if _data == null:
		return 0.0
	if _data.ads_time <= 0.0:
		return target
	return move_toward(value, target, maxf(delta, 0.0) / _data.ads_time)
