# Bounded display model; each line captures names at event time, including departures.
class_name KillFeed
extends RefCounted

var capacity: int = 6
var lines: Array[String] = []


func record(victim: String, killer: String, weapon: StringName, headshot: bool) -> void:
	var cause: String = String(weapon) if not weapon.is_empty() else "environment"
	lines.append("%s  [%s%s]  %s" % [killer, cause, " / HEAD" if headshot else "", victim])
	while lines.size() > capacity:
		lines.pop_front()
