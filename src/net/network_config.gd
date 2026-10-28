class_name NetworkConfig
extends Resource

const PROTOCOL_VERSION: int = 4
const DEFAULT_PORT: int = 7777
const DEFAULT_MAX_CLIENTS: int = 32
const MAX_PORT: int = 65535
const MAX_CLIENTS: int = 4095
const CHANNEL_COUNT: int = 4

@export_range(1, 64) var nickname_min_length: int = 2
@export_range(1, 64) var nickname_max_length: int = 24
@export var nickname_pattern: String = "^[A-Za-zА-Яа-яЁё0-9_-]+$"
@export_range(0.1, 60.0) var handshake_timeout_seconds: float = 5.0
@export_range(0.1, 2.0) var kick_grace_seconds: float = 0.2
@export_range(0.1, 5.0) var ping_interval_seconds: float = 0.5
@export_range(0.1, 10.0) var ping_timeout_seconds: float = 2.0
@export_range(0.01, 1.0) var rtt_smoothing: float = 0.2
@export_range(0.01, 1.0) var clock_smoothing: float = 0.2
@export_range(1, 2) var jitter_buffer_ticks: int = 2
@export_range(0.01, 0.5) var tick_slew_fraction: float = 0.25
@export_range(4, 8) var input_history_count: int = 6
@export_range(8, 256) var input_queue_capacity: int = 128
@export_range(0, 5) var input_repeat_ticks: int = 5
@export_range(0.1, 1.0) var input_max_future_seconds: float = 1.0
@export_range(0.1, 2.0) var input_max_age_seconds: float = 1.0


static func valid_port(port: int) -> bool:
	return port > 0 and port <= MAX_PORT


static func valid_max_clients(count: int) -> bool:
	return count > 0 and count <= MAX_CLIENTS
