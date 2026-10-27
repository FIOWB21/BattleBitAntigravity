class_name GrenadeStockConfig
extends Resource

@export var capacity: int = 3
@export var initial_count: int = 3


func is_valid() -> bool:
	return capacity >= 0 and initial_count >= 0 and initial_count <= capacity
