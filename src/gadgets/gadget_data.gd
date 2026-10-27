# Базовые параметры без механики конкретного класса.
class_name GadgetData
extends EquipmentData

@export var max_charges: int = 2
@export var cooldown: float = 0.5
@export var reload_time: float = 1.5
@export var deployable_scene: PackedScene
@export var placement: DeploymentConfig


func is_valid() -> bool:
	return max_charges >= 0 and is_finite(cooldown) and cooldown >= 0.0 \
		and is_finite(reload_time) and reload_time >= 0.0
