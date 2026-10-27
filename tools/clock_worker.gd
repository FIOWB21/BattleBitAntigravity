# Separate-process fixture using the production transport, clock and console.
extends SceneTree

const TIMEOUT_SECONDS: float = 15.0
const SAMPLE_INTERVAL: float = 0.05
var _net: Node
var _overlay: CanvasLayer
var _options: Dictionary[String, String] = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 0
	OS.low_processor_usage_mode_sleep_usec = 1000
	_net = root.get_node("Net")
	for arg: String in OS.get_cmdline_user_args():
		_options[arg.get_slice("=", 0)] = arg.substr(arg.find("=") + 1)
	if _options.get("--role", "client") == "server":
		await _server()
	else:
		await _client()


func _server() -> void:
	if _net.start_server(int(_options["--port"]), 8, false) != OK:
		quit(1)
		return
	print("CLOCK READY")
	var deadline: int = Time.get_ticks_msec() + int(TIMEOUT_SECONDS * NetClock.MS_PER_SECOND)
	while Time.get_ticks_msec() < deadline:
		print("CLOCK SERVER ", JSON.stringify({"tick": _net.tick, "time": Time.get_unix_time_from_system()}))
		if FileAccess.file_exists(_options["--stop-file"]):
			break
		await create_timer(SAMPLE_INTERVAL).timeout
	_net.disconnect_all()
	await process_frame
	quit(0)


func _client() -> void:
	_net.local_nickname = _options.get("--nickname", "ClockClient")
	var scene: PackedScene = load("res://src/ui/debug_overlay.tscn") as PackedScene
	_overlay = scene.instantiate() as CanvasLayer
	root.add_child(_overlay)
	_overlay.set_overlay_visible(true)
	_overlay.execute_command("net_sim %s %s" % [_options.get("--delay", "100"), _options.get("--loss", "0")])
	if _net.join("127.0.0.1", int(_options["--port"])) != OK:
		quit(1)
		return
	await _observe(float(_options.get("--hold", "5.0")))
	await _capture()
	_net.disconnect_all()
	print("CLOCK RESET ", JSON.stringify({"tick": _net.tick, "samples": _net.clock.sample_count,
		"ping": root.get_node("Game").debug["ping_ms"], "nodes": _net.time_sync.get_child_count()}))
	await process_frame
	quit(0)


func _observe(duration: float) -> void:
	var started: int = Time.get_ticks_msec()
	var recover_after: float = float(_options.get("--recover", "-1"))
	var recovered: bool = false
	while float(Time.get_ticks_msec() - started) / NetClock.MS_PER_SECOND < duration:
		var elapsed: float = float(Time.get_ticks_msec() - started) / NetClock.MS_PER_SECOND
		if not recovered and recover_after >= 0.0 and elapsed >= recover_after:
			print("CLOCK RECOVER samples=", _net.clock.sample_count, " tick=", _net.tick,
				" probes=", _net.time_sync.probe_count)
			_overlay.execute_command("net_sim 100 0")
			recovered = true
		if _net.clock.is_synchronized:
			_record_client()
		await create_timer(SAMPLE_INTERVAL).timeout


func _record_client() -> void:
	var clock: NetClock = _net.clock as NetClock
	var measured_ms: float = clock.rtt_seconds * NetClock.MS_PER_SECOND
	print("CLOCK SAMPLE ", JSON.stringify({"tick": _net.tick, "ping": measured_ms,
		"estimate": clock.estimated_server_tick(Time.get_ticks_usec()), "lead": clock.lead_ticks(),
		"samples": clock.sample_count, "probes": _net.time_sync.probe_count, "time": Time.get_unix_time_from_system(),
		"overlay_ok": _overlay.format_stats_text().contains("Ping: %d ms" % int(measured_ms))}))


func _capture() -> void:
	if not _options.has("--capture") or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(_options["--capture"])
	print("CLOCK CAPTURE result=", result)
