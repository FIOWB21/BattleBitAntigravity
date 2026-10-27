# Параметры размещённой взрывчатки; один профиль взрыва для людей и техники.
class_name ChargeConfig
extends Resource

@export var blast: ProjectileData
@export var vehicle_multiplier: float = 3.0
@export var arming_time: float = 1.0
@export var vehicle_trigger: bool = false
@export var trigger_radius: float = 1.5
@export var max_active: int = 4
@export var blast_offset: Vector3 = Vector3(0.0, 0.15, 0.0)


func is_valid() -> bool:
	return blast != null and is_finite(blast.radius) and blast.radius > 0.0 \
		and is_finite(blast.damage) and blast.damage > 0.0 \
		and is_finite(vehicle_multiplier) and vehicle_multiplier > 0.0 \
		and is_finite(arming_time) and arming_time >= 0.0 \
		and is_finite(trigger_radius) and trigger_radius > 0.0 and max_active > 0 \
		and blast_offset.is_finite()
