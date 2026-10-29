# Глобальная шина событий. Добавляем сигналы только когда они реально нужны шагам.
extends Node

@warning_ignore("unused_signal")
signal player_spawned(peer_id: int)
@warning_ignore("unused_signal")
signal player_died(victim_id: int, killer_id: int, weapon_id: StringName, headshot: bool)
@warning_ignore("unused_signal")
signal hit_confirmed(zone: int, killed: bool)
@warning_ignore("unused_signal")
signal damage_indicated(direction: Vector3)
@warning_ignore("unused_signal")
signal settings_changed()
