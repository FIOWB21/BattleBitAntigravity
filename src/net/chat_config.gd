class_name ChatConfig
extends Resource

@export_range(1, 1024) var max_length: int = 256
@export_range(1, 4096) var max_request_length: int = 1024
@export_range(1, 20) var burst_count: int = 3
@export_range(0.1, 60.0) var window_seconds: float = 5.0
@export_range(1, 100) var history_count: int = 8


func is_valid() -> bool:
	return max_length > 0 and max_request_length >= max_length and burst_count > 0 \
		and is_finite(window_seconds) and window_seconds > 0.0 and history_count > 0
