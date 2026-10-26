# Ресурс конфигурации множителей урона и геометрии зон хитбоксов игрока.
class_name HitboxConfig
extends Resource

@export var head_mult: float = 2.0
@export var torso_mult: float = 1.0
@export var arms_mult: float = 0.8
@export var legs_mult: float = 0.75

@export var head_radius: float = 0.15
@export var head_radius_max_height_ratio: float = 0.24
@export var min_body_height: float = 0.06
@export var legs_height_ratio: float = 0.5

@export var torso_width: float = 0.32
@export var torso_depth: float = 0.28

@export var arm_width: float = 0.14
@export var arm_depth: float = 0.24
@export var arm_gap: float = 0.01
@export var arm_height_ratio: float = 0.9

@export var legs_width: float = 0.36
@export var legs_depth: float = 0.28


func multiplier_for(zone: int) -> float:
	match zone:
		HitboxZone.HEAD:
			return head_mult
		HitboxZone.TORSO:
			return torso_mult
		HitboxZone.ARMS:
			return arms_mult
		HitboxZone.LEGS:
			return legs_mult
		_:
			return 1.0
