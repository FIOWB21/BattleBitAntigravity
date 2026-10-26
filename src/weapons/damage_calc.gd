# Чистый расчёт урона одной пули по данным оружия и множителю попавшей зоны.
class_name DamageCalc
extends RefCounted


static func compute(weapon: WeaponData, distance: float, zone: HitboxZone) -> float:
	if weapon == null or zone == null or zone.zone == HitboxZone.NONE:
		return 0.0
	return maxf(weapon.damage_at(maxf(distance, 0.0)), 0.0) * maxf(zone.damage_mult, 0.0)
