# Серверный интерфейс снабжения: fraction — доля полного запаса, магазин не меняется.
class_name AmmoReceiver
extends Node

@export var weapon: Weapon


func add_ammo(fraction: float) -> int:
	if not is_inside_tree() or not multiplayer.is_server() or not is_instance_valid(weapon):
		return 0
	if not is_finite(fraction) or fraction <= 0.0:
		return 0
	var amount: int = floori(weapon.reserve_capacity() * minf(fraction, 1.0))
	return weapon.add_reserve_ammo(amount)
