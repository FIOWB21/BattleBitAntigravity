extends GutTest


func test_sanitizer_removes_controls_and_disables_all_bbcode() -> void:
	var raw: String = " \u0001Привет\t\n\r\u007f\u0085\u200b\u202e\u2066\ufeff [b]мир[/b] "
	assert_eq(ChatPolicy.sanitize(raw, 256), "Привет (b)мир(/b)")
	assert_eq(ChatPolicy.sanitize("[url=https://example.com]link[/url]", 256),
		"(url=https://example.com)link(/url)")
	assert_eq(ChatPolicy.sanitize("😀Україна", 3), "😀Ук")
	assert_eq(ChatPolicy.sanitize("\n\t\u0001", 256), "")
	assert_eq(ChatPolicy.sanitize("abcd", 0), "")
	assert_eq(ChatPolicy.sanitize("abcd", -1), "")


func test_all_c0_c1_controls_are_removed_and_sanitizing_is_idempotent() -> void:
	var raw: String = ""
	# Godot Strings reject NUL before user code; cover every representable C0.
	for code: int in range(1, 32):
		raw += String.chr(code)
	for code: int in range(127, 160):
		raw += String.chr(code)
	assert_eq(ChatPolicy.sanitize(raw + "OK", 256), "OK")
	for value: String in ["[img]x[/img]", "ёжик 😀", "a\u2028b\u2069c", " a b "]:
		var clean: String = ChatPolicy.sanitize(value, 256)
		assert_eq(ChatPolicy.sanitize(clean, 256), clean)
		assert_false(clean.contains("["))
		assert_false(clean.contains("]"))


func test_sliding_window_exact_boundary_and_denials_do_not_extend_it() -> void:
	var config: ChatConfig = ChatConfig.new()
	var policy: ChatPolicy = ChatPolicy.new()
	for index: int in range(config.burst_count):
		assert_true(policy.allow(42, index, config))
	assert_false(policy.allow(42, 100, config))
	assert_false(policy.allow(42, 4999999, config))
	assert_true(policy.allow(42, 5000000, config))
	assert_false(policy.allow(42, 5000000, config))
	assert_true(policy.allow(42, 5000001, config))
	assert_true(policy.allow(42, 5000002, config))
	assert_false(policy.allow(42, 5000002, config))


func test_peer_budgets_are_independent_bounded_and_forgotten_on_disconnect() -> void:
	var config: ChatConfig = ChatConfig.new()
	var policy: ChatPolicy = ChatPolicy.new()
	for index: int in range(100):
		policy.allow(42, 100, config)
	assert_eq(policy._requests[42].size(), config.burst_count)
	assert_true(policy.allow(43, 100, config))
	assert_false(policy.allow(42, 99, config))
	policy.forget(42)
	assert_true(policy.allow(42, 100, config))
	policy.clear()
	assert_true(policy._requests.is_empty())
	assert_false(policy.allow(0, 100, config))
	assert_false(policy.allow(42, -1, config))
	assert_false(policy.allow(42, 100, null))


func test_invalid_config_fails_closed() -> void:
	var config: ChatConfig = load("res://src/net/default_chat.tres") as ChatConfig
	assert_true(config.is_valid())
	config = config.duplicate() as ChatConfig
	config.max_length = 0
	assert_false(config.is_valid())
	assert_false(ChatPolicy.new().allow(42, 100, config))
	config.max_length = 256
	for duration: float in [-1.0, 0.0, NAN, INF]:
		config.window_seconds = duration
		assert_false(config.is_valid())


func test_admin_disabled_without_password_and_permissions_do_not_leak_between_peers() -> void:
	var admin: ChatAdmin = ChatAdmin.new()
	assert_false(admin.login(42, "", ""))
	assert_false(admin.login(42, "bad", "secret"))
	assert_false(admin.is_authorized(42, "secret"))
	assert_true(admin.login(42, "a=b c", "a=b c"))
	assert_true(admin.is_authorized(42, "a=b c"))
	assert_false(admin.is_authorized(43, "a=b c"))
	assert_false(admin.is_authorized(42, ""))
	assert_false(admin.login(42, "bad", "a=b c"))
	assert_false(admin.is_authorized(42, "a=b c"))
	assert_true(admin.login(42, "secret", "secret"))
	admin.forget(42)
	assert_false(admin.is_authorized(42, "secret"))
	assert_true(admin.login(42, "secret", "secret"))
	admin.clear()
	assert_false(admin.is_authorized(42, "secret"))
