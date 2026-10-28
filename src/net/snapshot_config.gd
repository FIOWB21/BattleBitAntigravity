class_name SnapshotConfig
extends Resource

@export var position_min: Vector3 = Vector3(-256.0, -64.0, -256.0)
@export var position_max: Vector3 = Vector3(256.0, 192.0, 256.0)
@export_range(1.0, 256.0) var velocity_limit: float = 64.0
@export_range(2, 2) var interval_ticks: int = 2
@export_range(0.0, 0.5) var interpolation_seconds: float = 0.1
@export_range(0.0, 0.1) var extrapolation_seconds: float = 0.1
@export_range(2, 128) var buffer_capacity: int = 32


func is_valid() -> bool:
	return position_min.is_finite() and position_max.is_finite() \
		and position_max.x > position_min.x and position_max.y > position_min.y \
		and position_max.z > position_min.z and is_finite(velocity_limit) and velocity_limit > 0.0 \
		and interval_ticks == 2 and buffer_capacity >= 2 and buffer_capacity <= 128 \
		and is_finite(interpolation_seconds) and interpolation_seconds >= 0.0 \
		and is_finite(extrapolation_seconds) and extrapolation_seconds >= 0.0 \
		and extrapolation_seconds <= 0.1
