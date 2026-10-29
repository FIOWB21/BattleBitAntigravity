# Plain text only; request budgets use the server's monotonic clock.
class_name ChatPolicy
extends RefCounted

const USEC_PER_SECOND: int = 1000000
const FIRST_PRINTABLE: int = 32
const DELETE_CHARACTER: int = 127
const LAST_C1_CONTROL: int = 159

var _requests: Dictionary[int, PackedInt64Array] = {}


static func sanitize(raw: String, limit: int) -> String:
	var result: String = ""
	for index: int in range(raw.length()):
		var code: int = raw.unicode_at(index)
		if _is_control(code):
			continue
		var character: String = raw[index]
		if character == "[":
			character = "("
		elif character == "]":
			character = ")"
		result += character
	return result.strip_edges().left(maxi(0, limit)).strip_edges()


static func _is_control(code: int) -> bool:
	return code < FIRST_PRINTABLE or (code >= DELETE_CHARACTER and code <= LAST_C1_CONTROL) \
		or code == 0x00AD or code == 0x061C or code == 0xFEFF \
		or (code >= 0x200B and code <= 0x200F) or (code >= 0x2028 and code <= 0x202E) \
		or (code >= 0x2060 and code <= 0x206F) or (code >= 0xFFF9 and code <= 0xFFFB) \
		or (code >= 0xE0000 and code <= 0xE007F)


func allow(peer: int, now_usec: int, config: ChatConfig) -> bool:
	if peer <= 0 or now_usec < 0 or config == null or not config.is_valid():
		return false
	var recent: PackedInt64Array = _requests.get(peer, PackedInt64Array())
	var cutoff: int = now_usec - ceili(config.window_seconds * USEC_PER_SECOND)
	while not recent.is_empty() and recent[0] <= cutoff:
		recent.remove_at(0)
	if recent.size() >= config.burst_count:
		return false
	if not recent.is_empty() and now_usec < recent[recent.size() - 1]:
		return false
	recent.append(now_usec)
	_requests[peer] = recent
	return true


func forget(peer: int) -> void:
	_requests.erase(peer)


func clear() -> void:
	_requests.clear()
