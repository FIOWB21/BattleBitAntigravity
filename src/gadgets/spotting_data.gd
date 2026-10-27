class_name SpottingData
extends GadgetData

@export var reach: float = 250.0
@export var duration: float = 8.0
@export var capacity: int = 32
@export var marker_offset: Vector3 = Vector3(0.0, 2.2, 0.0)


func is_valid() -> bool:
	return super.is_valid() and is_finite(reach) and reach > 0.0 \
		and is_finite(duration) and duration > 0.0 and capacity > 0 and marker_offset.is_finite()
