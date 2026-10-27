# Правила ранения матча; длительности и разрешения задаются данными.
class_name MatchRules
extends Resource

@export var downed_enabled: bool = true
@export var bleedout_time: float = 20.0
@export var revive_time: float = 3.0
@export var revive_health_fraction: float = 0.3
@export var revive_distance: float = 2.0
@export var revive_perk: StringName = &"revive"


func is_valid() -> bool:
	return is_finite(bleedout_time) and bleedout_time > 0.0 \
		and is_finite(revive_time) and revive_time > 0.0 \
		and is_finite(revive_health_fraction) and revive_health_fraction > 0.0 \
		and revive_health_fraction <= 1.0 \
		and is_finite(revive_distance) and revive_distance > 0.0 \
		and not revive_perk.is_empty()
