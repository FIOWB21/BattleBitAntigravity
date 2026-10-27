# Прогретая запись пула, общая для серверного срока и косметической метки.
class_name SpotMark
extends RefCounted

var target: CombatAffiliation
var team_id: int = 0
var remaining: float = 0.0


func is_visible_to(team: int) -> bool:
	return remaining > 0.0 and team > 0 and team == team_id \
		and is_instance_valid(target) and target.is_alive() and target.team_id != team
