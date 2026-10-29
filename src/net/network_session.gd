# Admission memory belongs to one running server, never to a client profile.
class_name NetworkSession
extends RefCounted

const IPV6_GROUP_COUNT: int = 8
const OCTET_BITS: int = 8
const OCTET_MASK: int = 255

var _blocked: Dictionary[String, bool] = {}
var _names: Dictionary[int, String] = {}
var _teams: Dictionary[String, int] = {}


func configure(blocked_ips: PackedStringArray) -> void:
	clear()
	for address: String in blocked_ips:
		ban_ip(address)


static func normalize_ip(address: String) -> String:
	var normalized: String = address.strip_edges().to_lower()
	if not normalized.is_valid_ip_address():
		return ""
	if not normalized.contains(":"):
		var octets: PackedStringArray = normalized.split(".")
		for index: int in range(octets.size()):
			octets[index] = str(octets[index].to_int())
		return ".".join(octets)
	var groups: PackedStringArray = _ipv6_groups(normalized)
	if ":".join(groups).begins_with("0000:0000:0000:0000:0000:ffff:"):
		var high: int = groups[6].hex_to_int()
		var low: int = groups[7].hex_to_int()
		return "%d.%d.%d.%d" % [high >> OCTET_BITS, high & OCTET_MASK, low >> OCTET_BITS, low & OCTET_MASK]
	return ":".join(groups)


static func _ipv6_groups(address: String) -> PackedStringArray:
	if address.contains("."):
		var boundary: int = address.rfind(":") + 1
		var octets: PackedStringArray = address.substr(boundary).split(".")
		address = address.left(boundary) + "%x:%x" % [
			(octets[0].to_int() << OCTET_BITS) | octets[1].to_int(),
			(octets[2].to_int() << OCTET_BITS) | octets[3].to_int()]
	var halves: PackedStringArray = address.split("::")
	var head: PackedStringArray = halves[0].split(":", false)
	var tail: PackedStringArray = halves[1].split(":", false) if halves.size() > 1 else PackedStringArray()
	var groups: PackedStringArray = PackedStringArray()
	for group: String in head:
		groups.append("%04x" % group.hex_to_int())
	for index: int in range(IPV6_GROUP_COUNT - head.size() - tail.size()):
		groups.append("0000")
	for group: String in tail:
		groups.append("%04x" % group.hex_to_int())
	return groups


func ban_ip(address: String) -> bool:
	var normalized: String = normalize_ip(address)
	if normalized.is_empty():
		return false
	_blocked[normalized] = true
	return true


func unban_ip(address: String) -> bool:
	return _blocked.erase(normalize_ip(address))


func is_blocked(address: String) -> bool:
	return _blocked.has(normalize_ip(address))


func blacklist() -> Array[String]:
	var result: Array[String] = _blocked.keys()
	result.sort()
	return result


func admit(peer: int, nickname: String) -> void:
	_names[peer] = nickname.to_lower()


func remember_team(peer: int, team: int) -> void:
	if _names.has(peer) and team > 0:
		_teams[_names[peer]] = team


func team_for(nickname: String, fallback: int = 1) -> int:
	return _teams.get(nickname.to_lower(), fallback)


func forget(peer: int) -> void:
	_names.erase(peer)


func clear() -> void:
	_blocked.clear()
	_names.clear()
	_teams.clear()
