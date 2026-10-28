extends GutTest

var _config: NetworkConfig = preload("res://src/net/default_network.tres")


func test_nickname_length_and_alphabet() -> void:
	for nickname: String in ["AB", "Soldier_01", "Игрок-2", "Ёжик", "A".repeat(24)]:
		assert_true(HandshakeRules.valid_nickname(nickname, _config), nickname)
	for nickname: String in ["", "A", "A".repeat(25), " two", "two words", "a\nb", "ab\n", "ab\r", "a\tb", "<a>", "ab."]:
		assert_false(HandshakeRules.valid_nickname(nickname, _config), nickname)


func test_rejection_reason_and_case_insensitive_uniqueness() -> void:
	var names: Dictionary[int, String] = {1: "Host", 2: "Игрок"}
	assert_eq(_reason(NetworkConfig.PROTOCOL_VERSION, "New_1", "secret", names), "")
	assert_eq(_reason(1, "New_1", "secret", names), "protocol_mismatch")
	assert_eq(_reason(NetworkConfig.PROTOCOL_VERSION, "!", "secret", names), "invalid_nickname")
	assert_eq(_reason(NetworkConfig.PROTOCOL_VERSION, "HOST", "secret", names), "nickname_in_use")
	assert_eq(_reason(NetworkConfig.PROTOCOL_VERSION, "игрок", "secret", names), "nickname_in_use")
	assert_eq(_reason(NetworkConfig.PROTOCOL_VERSION, "New_1", "bad", names), "wrong_password")
	assert_eq(names.size(), 2, "Validation never mutates admission state")


func test_empty_password_and_configured_nickname_limits() -> void:
	var names: Dictionary[int, String] = {}
	assert_eq(HandshakeRules.rejection_reason(NetworkConfig.PROTOCOL_VERSION, "Player", "", "", names, _config), "")
	var custom: NetworkConfig = _config.duplicate() as NetworkConfig
	custom.nickname_min_length = 3
	custom.nickname_max_length = 4
	assert_false(HandshakeRules.valid_nickname("AB", custom))
	assert_true(HandshakeRules.valid_nickname("ABCD", custom))
	assert_false(HandshakeRules.valid_nickname("ABCDE", custom))


func test_port_and_capacity_boundaries() -> void:
	for port: int in [1, 7777, 65535]:
		assert_true(NetworkConfig.valid_port(port))
	for port: int in [-1, 0, 65536]:
		assert_false(NetworkConfig.valid_port(port))
	for count: int in [1, 32, 4095]:
		assert_true(NetworkConfig.valid_max_clients(count))
	for count: int in [-1, 0, 4096]:
		assert_false(NetworkConfig.valid_max_clients(count))


func _reason(version: int, nickname: String, password: String, names: Dictionary[int, String]) -> String:
	return HandshakeRules.rejection_reason(version, nickname, password, "secret", names, _config)
