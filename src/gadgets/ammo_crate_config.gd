class_name AmmoCrateConfig
extends Resource

@export var radius: float = 4.0
@export var interval: float = 1.0
@export var ammo_fraction: float = 0.2
@export var grenades_per_pulse: int = 1


func is_valid() -> bool:
	return is_finite(radius) and radius > 0.0 \
		and is_finite(interval) and interval > 0.0 \
		and is_finite(ammo_fraction) and ammo_fraction > 0.0 and ammo_fraction <= 1.0 \
		and grenades_per_pulse >= 0
