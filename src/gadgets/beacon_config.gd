class_name BeaconConfig
extends Resource

@export var max_health: float = 100.0
@export var offsets: PackedVector3Array = PackedVector3Array([
	Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 1.5), Vector3(0, 0, -1.5)])
@export var probe_up: float = 2.0
@export var probe_down: float = 4.0
@export var min_up_dot: float = 0.7
@export var floor_margin: float = 0.02
@export_flags_3d_physics var ground_mask: int = 1 | 16 | 64
@export_flags_3d_physics var clearance_mask: int = 1 | 2 | 16 | 64


func is_valid() -> bool:
	if not is_finite(max_health) or max_health <= 0.0 or offsets.is_empty() \
		or not is_finite(probe_up) or probe_up <= 0.0 \
		or not is_finite(probe_down) or probe_down <= 0.0 \
		or not is_finite(min_up_dot) or min_up_dot < 0.0 or min_up_dot > 1.0 \
		or not is_finite(floor_margin) or floor_margin <= 0.0:
		return false
	for offset: Vector3 in offsets:
		if not offset.is_finite():
			return false
	return true
