class_name NetworkConfig
extends Resource

const PROTOCOL_VERSION: int = 1
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


static func valid_port(port: int) -> bool:
	return port > 0 and port <= MAX_PORT


static func valid_max_clients(count: int) -> bool:
	return count > 0 and count <= MAX_CLIENTS
