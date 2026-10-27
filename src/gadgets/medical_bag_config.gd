class_name MedicalBagConfig
extends Resource

@export var radius: float = 4.0
@export var heal_per_second: float = 10.0
@export var lifetime: float = 20.0


func is_valid() -> bool:
	return is_finite(radius) and radius > 0.0 \
		and is_finite(heal_per_second) and heal_per_second > 0.0 \
		and is_finite(lifetime) and lifetime > 0.0
