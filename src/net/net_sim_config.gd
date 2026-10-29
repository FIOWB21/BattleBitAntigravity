# Debug-only impairment profile shared by the two outgoing directions of a link.
class_name NetSimConfig
extends Resource

const PERCENT: float = 100.0
const MAX_DELAY_MS: int = 2000
const USEC_PER_MS: int = 1000

@export_range(0, 2000) var rtt_ms: int = 0
@export_range(0, 100) var loss_percent: float = 0.0
@export_range(0, 2000) var jitter_ms: int = 0
@export_range(0, 100) var duplicate_percent: float = 0.0
@export_range(0, 100) var reorder_percent: float = 0.0
@export_range(1, 2000) var reorder_hold_ms: int = 50


func is_valid() -> bool:
	return rtt_ms >= 0 and rtt_ms <= MAX_DELAY_MS and jitter_ms >= 0 \
		and jitter_ms <= MAX_DELAY_MS and reorder_hold_ms > 0 \
		and reorder_hold_ms <= MAX_DELAY_MS and valid_percent(loss_percent) \
		and valid_percent(duplicate_percent) and valid_percent(reorder_percent)


static func valid_percent(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= PERCENT
