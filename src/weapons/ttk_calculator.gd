# Нижняя граница TTK в одном магазине: все дробины попали, первый выстрел в t=0.
class_name TtkCalculator
extends RefCounted


static func shots_to_kill(data: WeaponData, distance: float, health: float,
		zone_multiplier: float) -> int:
	if data == null or data.projectile_data != null or data.pellets <= 0:
		return 0
	if not is_finite(distance) or not is_finite(health) or not is_finite(zone_multiplier):
		return 0
	if distance < 0.0 or distance > data.hitscan_range or health <= 0.0 or zone_multiplier <= 0.0:
		return 0
	var damage: float = data.damage_at(distance) * zone_multiplier * data.pellets
	if not is_finite(damage) or damage <= 0.0:
		return 0
	return ceili(health / damage)


static func interval_ticks(data: WeaponData, tick_rate: int) -> int:
	if data == null or not is_finite(data.rpm) or data.rpm <= 0.0 or tick_rate <= 0:
		return 0
	var ticks: int = maxi(1, ceili(data.cooldown() * tick_rate))
	# SEMI требует отпускания спуска хотя бы на одном промежуточном тике.
	if not data.fire_modes.is_empty() and data.fire_modes[0] == WeaponData.FireMode.SEMI:
		ticks = maxi(2, ticks)
	return ticks


static func seconds(data: WeaponData, distance: float, health: float,
		zone_multiplier: float, tick_rate: int) -> float:
	var shots: int = shots_to_kill(data, distance, health, zone_multiplier)
	var interval: int = interval_ticks(data, tick_rate)
	if shots <= 0 or interval <= 0 or shots > data.mag_size or data.fire_modes.is_empty():
		return INF
	# Для очередей граница магазина допускается лишь внутри одной очереди.
	if data.fire_modes[0] == WeaponData.FireMode.BURST and shots > data.burst_count:
		return INF
	return float((shots - 1) * interval) / tick_rate
