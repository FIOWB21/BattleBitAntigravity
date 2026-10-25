extends GutTest

const TEST_CFG_PATH: String = "user://test_settings_step_0_4.cfg"


func before_each() -> void:
	Settings.reset_to_defaults()
	Log.min_level = Log.Level.DEBUG
	Game.set_state(Game.State.MENU)
	Game.detect_runtime_flags(PackedStringArray(), false)


func after_each() -> void:
	if FileAccess.file_exists(TEST_CFG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG_PATH))
	Settings.reset_to_defaults()
	Log.min_level = Log.Level.DEBUG
	Game.set_state(Game.State.MENU)
	Game.detect_runtime_flags(PackedStringArray(), false)


func test_settings_defaults() -> void:
	assert_almost_eq(Settings.get_sensitivity(), Settings.DEFAULT_SENSITIVITY, 0.0001, "default sensitivity")
	assert_almost_eq(Settings.get_fov(), Settings.DEFAULT_FOV, 0.0001, "default fov")
	assert_almost_eq(Settings.get_volume(), Settings.DEFAULT_VOLUME, 0.0001, "default volume")
	assert_eq(Settings.get_graphics(), Settings.DEFAULT_GRAPHICS, "default graphics")


func test_settings_write_and_read_config_file() -> void:
	var signal_count: Array[int] = [0]
	var on_changed: Callable = func() -> void:
		signal_count[0] += 1
	Events.settings_changed.connect(on_changed)

	Settings.set_sensitivity(0.45)
	Settings.set_fov(105.0)
	Settings.set_volume(0.65)
	Settings.set_graphics("medium")
	assert_gt(signal_count[0], 0, "settings_changed signal must be emitted")

	var save_err: Error = Settings.save_settings(TEST_CFG_PATH)
	assert_eq(save_err, OK, "save_settings should return OK")
	assert_true(FileAccess.file_exists(TEST_CFG_PATH), "config file must exist on disk")

	Settings.reset_to_defaults()
	assert_almost_eq(Settings.get_fov(), Settings.DEFAULT_FOV, 0.0001, "fov reset to default before load")

	var load_err: Error = Settings.load_settings(TEST_CFG_PATH)
	assert_eq(load_err, OK, "load_settings should return OK")
	assert_almost_eq(Settings.get_sensitivity(), 0.45, 0.0001, "loaded sensitivity matches")
	assert_almost_eq(Settings.get_fov(), 105.0, 0.0001, "loaded fov matches")
	assert_almost_eq(Settings.get_volume(), 0.65, 0.0001, "loaded volume matches")
	assert_eq(Settings.get_graphics(), "medium", "loaded graphics matches")

	Events.settings_changed.disconnect(on_changed)


func test_log_info_and_role_prefix() -> void:
	Game.is_server = false
	Log.i("test")
	assert_has(Log.last_line, "[CLIENT]", "client role prefix in log output")
	assert_has(Log.last_line, "[INFO]", "INFO level in log output")
	assert_has(Log.last_line, "test", "message body in log output")

	Game.is_server = true
	Log.w("server warning")
	assert_has(Log.last_line, "[SERVER]", "server role prefix in log output")
	assert_has(Log.last_line, "[WARN]", "WARN level in log output")

	Log.min_level = Log.Level.WARN
	var prev_line: String = Log.last_line
	Log.d("ignored debug")
	assert_eq(Log.last_line, prev_line, "messages below min_level must be ignored")


func test_game_state_and_runtime_flags() -> void:
	assert_true(Game.is_in_menu(), "starts in menu")
	Game.set_state(Game.State.IN_GAME)
	assert_true(Game.is_in_game(), "switches to in_game")

	Game.detect_runtime_flags(PackedStringArray(["--server"]), false)
	assert_true(Game.is_dedicated, "--server sets is_dedicated")
	assert_true(Game.is_server, "--server sets is_server")

	Game.detect_runtime_flags(PackedStringArray(), true)
	assert_true(Game.is_dedicated, "dedicated_server feature sets is_dedicated")
	assert_true(Game.is_server, "dedicated_server feature sets is_server")


func test_events_and_net_autoloads_exist() -> void:
	assert_not_null(Events, "Events autoload exists")
	assert_true(Events.has_signal("player_spawned"), "Events has player_spawned")
	assert_true(Events.has_signal("player_died"), "Events has player_died")
	assert_true(Events.has_signal("settings_changed"), "Events has settings_changed")
	assert_not_null(Net, "Net autoload exists")
