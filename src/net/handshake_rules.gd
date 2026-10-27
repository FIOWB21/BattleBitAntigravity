class_name HandshakeRules
extends RefCounted


static func valid_nickname(nickname: String, config: NetworkConfig) -> bool:
	if nickname.length() < config.nickname_min_length:
		return false
	if nickname.length() > config.nickname_max_length:
		return false
	var pattern: RegEx = RegEx.create_from_string(config.nickname_pattern)
	var matched: RegExMatch = pattern.search(nickname)
	return matched != null and matched.get_string() == nickname


static func rejection_reason(
	version: int, nickname: String, supplied_password: String, server_password: String,
	nicknames: Dictionary[int, String], config: NetworkConfig
) -> String:
	if version != NetworkConfig.PROTOCOL_VERSION:
		return "protocol_mismatch"
	if not valid_nickname(nickname, config):
		return "invalid_nickname"
	var normalized: String = nickname.to_lower()
	for existing: String in nicknames.values():
		if existing.to_lower() == normalized:
			return "nickname_in_use"
	if supplied_password != server_password:
		return "wrong_password"
	return ""
