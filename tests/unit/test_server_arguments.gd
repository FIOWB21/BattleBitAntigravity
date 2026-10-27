extends GutTest


func after_each() -> void:
	Game.parse_server_arguments(PackedStringArray())


func test_defaults_and_all_server_options() -> void:
	assert_true(Game.parse_server_arguments(PackedStringArray()).is_empty())
	assert_eq(Game.server_port, 7777)
	assert_eq(Game.max_clients, 32)
	assert_eq(Game.map_id, "testbed")
	assert_eq(Game.server_password, "")
	var args: PackedStringArray = ["--server", "--port=9123", "--max=64", "--map=arena_2", "--password=a=b c"]
	assert_true(Game.parse_server_arguments(args).is_empty())
	assert_eq(Game.server_port, 9123)
	assert_eq(Game.max_clients, 64)
	assert_eq(Game.map_id, "arena_2")
	assert_eq(Game.server_password, "a=b c")


func test_invalid_values_missing_values_duplicates_and_unknown_options() -> void:
	for arg: String in ["--port=0", "--port=65536", "--port=text", "--port=1.5",
		"--max=0", "--max=4096", "--max=no", "--map=", "--map=../map", "--map=arena\n", "--port", "--unknown=1", "--server=yes"]:
		var errors: Array[String] = Game.parse_server_arguments(PackedStringArray([arg]))
		assert_eq(errors.size(), 1, arg)
	var duplicate: Array[String] = Game.parse_server_arguments(PackedStringArray(["--port=7777", "--port=8888"]))
	assert_eq(duplicate.size(), 1)
	assert_has(duplicate[0], "duplicate_argument")
	assert_eq(Game.server_port, 7777)


func test_parser_resets_state_and_does_not_leak_password_in_errors() -> void:
	Game.parse_server_arguments(PackedStringArray(["--password=secret", "--port=9000"]))
	var errors: Array[String] = Game.parse_server_arguments(PackedStringArray(["--password=secret", "--password=hidden"]))
	assert_false(str(errors).contains("secret"))
	assert_false(str(errors).contains("hidden"))
	Game.parse_server_arguments(PackedStringArray())
	assert_eq(Game.server_password, "")
	assert_eq(Game.server_port, 7777)
