extends GutTest

const OVERLAY_SCENE_PATH: String = "res://src/ui/debug_overlay.tscn"


func before_each() -> void:
	Game.reset_debug()
	Engine.max_fps = 0
	Log.min_level = Log.Level.DEBUG


func after_each() -> void:
	Net.time_sync.configure_simulation(0, 0.0)
	Game.reset_debug()
	Engine.max_fps = 0
	Log.min_level = Log.Level.DEBUG


func test_parse_command_handles_whitespace_and_args() -> void:
	var console: DebugConsole = DebugConsole.new()

	var empty_parsed: Dictionary = console.parse_command("   \t  ")
	assert_eq(empty_parsed["name"], "", "empty line returns empty command name")
	var empty_args: PackedStringArray = empty_parsed["args"]
	assert_eq(empty_args.size(), 0, "empty line returns zero args")

	var single_parsed: Dictionary = console.parse_command("  HELP ")
	assert_eq(single_parsed["name"], "help", "command name is lowercased and trimmed")
	var single_args: PackedStringArray = single_parsed["args"]
	assert_eq(single_args.size(), 0, "single command has no args")

	var multi_parsed: Dictionary = console.parse_command("  net_sim \t 120   3.5  ")
	assert_eq(multi_parsed["name"], "net_sim", "multi-arg command name parsed")
	var multi_args: PackedStringArray = multi_parsed["args"]
	assert_eq(multi_args.size(), 2, "two arguments parsed")
	assert_eq(multi_args[0], "120", "first argument matches")
	assert_eq(multi_args[1], "3.5", "second argument matches")


func test_builtin_commands_registered_as_callables() -> void:
	var console: DebugConsole = DebugConsole.new()
	var expected: Array[String] = ["help", "fps", "net_sim", "god", "noclip"]
	for cmd: String in expected:
		assert_true(console.commands.has(cmd), "commands dictionary has " + cmd)
		assert_true(console.commands[cmd] is Callable, cmd + " is mapped to a Callable")

	console.register_command(
		"echo_test",
		func(args: PackedStringArray) -> String:
			return "ECHO:" + ",".join(args)
	)
	var out: String = console.execute_command("echo_test alpha beta")
	assert_eq(out, "ECHO:alpha,beta", "custom Callable command executes with args")


func test_help_command_prints_command_list() -> void:
	var console: DebugConsole = DebugConsole.new()
	var out: String = console.execute_command("help")
	assert_has(out, "fps", "help output lists fps")
	assert_has(out, "god", "help output lists god")
	assert_has(out, "help", "help output lists help")
	assert_has(out, "net_sim", "help output lists net_sim")
	assert_has(out, "noclip", "help output lists noclip")
	assert_has(Log.last_line, "Available commands:", "help also prints to Log")


func test_fps_command_updates_engine_max_fps() -> void:
	var console: DebugConsole = DebugConsole.new()
	var out: String = console.execute_command("fps 120")
	assert_eq(Engine.max_fps, 120, "Engine.max_fps updated to 120")
	assert_eq(int(Game.debug["max_fps"]), 120, "Game.debug.max_fps updated to 120")
	assert_has(out, "120", "fps command confirms new value")

	var bad_out: String = console.execute_command("fps invalid")
	assert_has(bad_out, "Usage:", "invalid fps argument returns usage")
	assert_eq(Engine.max_fps, 120, "Engine.max_fps unchanged after invalid arg")


func test_net_sim_command_stores_values_in_game_debug() -> void:
	var console: DebugConsole = DebugConsole.new()
	var out: String = console.execute_command("net_sim 85 2.5")
	assert_eq(int(Game.debug["simulated_ping_ms"]), 85, "Requested delay stored separately")
	assert_eq(int(Game.debug["ping_ms"]), 0, "Command cannot fabricate measured RTT")
	assert_eq(Net.time_sync.simulated_rtt_ms, 85)
	assert_almost_eq(float(Game.debug["loss_percent"]), 2.5, 0.001, "Game.debug loss_percent set to 2.5")
	assert_almost_eq(float(Game.debug["loss_pct"]), 2.5, 0.001, "Game.debug loss_pct set to 2.5")
	assert_has(out, "85", "net_sim output contains ping")

	var bad_out: String = console.execute_command("net_sim -10 150")
	assert_has(bad_out, "Error:", "out-of-range net_sim returns error")
	assert_eq(Net.time_sync.simulated_rtt_ms, 85, "Delay unchanged after invalid command")


func test_god_and_noclip_hooks_toggle_flags() -> void:
	var console: DebugConsole = DebugConsole.new()
	assert_false(bool(Game.debug["god"]), "god initially false")
	console.execute_command("god")
	assert_true(bool(Game.debug["god"]), "god toggled to true")
	console.execute_command("god")
	assert_false(bool(Game.debug["god"]), "god toggled back to false")

	assert_false(bool(Game.debug["noclip"]), "noclip initially false")
	console.execute_command("noclip on")
	assert_true(bool(Game.debug["noclip"]), "noclip set to true")
	console.execute_command("noclip off")
	assert_false(bool(Game.debug["noclip"]), "noclip set to false")


func test_overlay_scene_toggles_and_formats_stats() -> void:
	var packed: PackedScene = load(OVERLAY_SCENE_PATH) as PackedScene
	assert_not_null(packed, "debug_overlay.tscn loads as PackedScene")
	var overlay: DebugOverlay = packed.instantiate() as DebugOverlay
	assert_not_null(overlay, "DebugOverlay instantiates")

	assert_false(overlay.is_overlay_visible(), "overlay hidden by default")
	overlay.toggle_overlay()
	assert_true(overlay.is_overlay_visible(), "overlay visible after toggle_overlay()")
	assert_true(overlay.visible, "CanvasLayer visible when overlay is active")
	overlay.toggle_overlay()
	assert_false(overlay.is_overlay_visible(), "overlay hidden after second toggle_overlay()")

	var f3_event: InputEventKey = InputEventKey.new()
	f3_event.pressed = true
	f3_event.keycode = KEY_F3
	overlay._input(f3_event)
	assert_true(overlay.is_overlay_visible(), "F3 key event enables overlay")

	var tilde_event: InputEventKey = InputEventKey.new()
	tilde_event.pressed = true
	tilde_event.keycode = KEY_QUOTELEFT
	overlay._input(tilde_event)
	assert_true(overlay.is_console_visible(), "backtick key event enables console")

	var stats: String = overlay.format_stats_text()
	assert_has(stats, "FPS:", "stats text has FPS")
	assert_has(stats, "Frame:", "stats text has Frame ms")
	assert_has(stats, "Memory:", "stats text has Memory")
	assert_has(stats, "Nodes:", "stats text has Nodes")
	assert_has(stats, "Pos:", "stats text has Pos")
	assert_has(stats, "Ping:", "stats text has Ping")

	overlay.free()


func test_overlay_in_tree_updates_ui_and_console_log() -> void:
	var packed: PackedScene = load(OVERLAY_SCENE_PATH) as PackedScene
	var overlay: DebugOverlay = packed.instantiate() as DebugOverlay
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(overlay)

	var stats_panel: Control = overlay.get_node("StatsPanel") as Control
	var console_panel: Control = overlay.get_node("ConsolePanel") as Control
	var output_label: RichTextLabel = overlay.get_node(
		"ConsolePanel/MarginContainer/VBoxContainer/OutputLabel"
	) as RichTextLabel

	overlay.toggle_overlay()
	assert_true(stats_panel.visible, "StatsPanel becomes visible in tree")
	overlay.toggle_console()
	assert_true(console_panel.visible, "ConsolePanel becomes visible in tree")

	var out: String = overlay.execute_command("help")
	assert_has(out, "Available commands:", "help returns command list")
	assert_has(output_label.get_parsed_text(), "Available commands:", "RichTextLabel displays output")

	tree.root.remove_child(overlay)
	overlay.free()
