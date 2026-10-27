# Геометрия размещения задаётся ресурсом, поза — симуляцией игрока.
class_name DeploymentConfig
extends Resource

@export var forward_distance: float = 1.5
@export var probe_up: float = 0.5
@export var probe_down: float = 3.0
@export var min_up_dot: float = 0.7
@export var clearance_size: Vector3 = Vector3(0.65, 0.35, 0.45)
@export var clearance_offset: float = 0.02
@export_flags_3d_physics var collision_mask: int = 1 | 16 | 64


func is_valid() -> bool:
	return is_finite(forward_distance) and forward_distance > 0.0 \
		and is_finite(probe_up) and probe_up > 0.0 \
		and is_finite(probe_down) and probe_down > 0.0 \
		and is_finite(min_up_dot) and min_up_dot > 0.0 and min_up_dot <= 1.0 \
		and clearance_size.is_finite() and clearance_size.x > 0.0 \
		and clearance_size.y > 0.0 and clearance_size.z > 0.0 \
		and is_finite(clearance_offset) and clearance_offset > 0.0
