# Credentials are never relayed, logged, or stored in client history.
class_name ChatAdmin
extends RefCounted

var _authorized: Dictionary[int, bool] = {}


func login(peer: int, supplied: String, configured: String) -> bool:
	if peer <= 0 or configured.is_empty() or supplied.sha256_text() != configured.sha256_text():
		_authorized.erase(peer)
		return false
	_authorized[peer] = true
	return true


func is_authorized(peer: int, configured: String) -> bool:
	return not configured.is_empty() and _authorized.has(peer)


func forget(peer: int) -> void:
	_authorized.erase(peer)


func clear() -> void:
	_authorized.clear()
