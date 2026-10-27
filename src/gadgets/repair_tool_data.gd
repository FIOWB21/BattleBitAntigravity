class_name RepairToolData
extends GadgetData

@export var reach: float = 4.0
@export var repair_per_second: float = 25.0
@export var heat_per_second: float = 0.25
@export var cooling_per_second: float = 0.2
@export var resume_heat: float = 0.35
@export_flags_3d_physics var ray_mask: int = 1 | 16 | 64


func is_valid() -> bool:
	return super.is_valid() and is_finite(reach) and reach > 0.0 \
		and is_finite(repair_per_second) and repair_per_second > 0.0 \
		and is_finite(heat_per_second) and heat_per_second > 0.0 \
		and is_finite(cooling_per_second) and cooling_per_second > 0.0 \
		and is_finite(resume_heat) and resume_heat >= 0.0 and resume_heat < 1.0
