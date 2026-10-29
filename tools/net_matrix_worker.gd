# Separate ENet processes using production clocks, input, prediction and fire RPCs.
extends SceneTree

const TIMEOUT_MS: int = 25000
const ROUTE_TICKS: int = 360
const SETTLE_SECONDS: float = 1.5
const SEED: int = 412
var _options: Dictionary[String, String] = {}
var _net: Node
var _menu: Control
var _actor: Node3D
var _failed: bool = false
var _route_distance: float = 0.0
var _route_peak: float = 0.0
var _route_ms: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.low_processor_usage_mode_sleep_usec = 1000
	for arg: String in OS.get_cmdline_user_args():
		_options[arg.get_slice("=", 0)] = arg.substr(arg.find("=") + 1)
	_net = root.get_node("Net")
	var game: Node = root.get_node("Game")
	game.is_dedicated = _options.get("--role", "client") == "server"
	game.server_port = int(_options["--port"])
	_menu = load("res://src/ui/main_menu.tscn").instantiate() as Control
	_menu.name = "MainMenu"
	root.add_child(_menu)
	_menu.port.value = int(_options["--port"])
	_menu.nickname.text = "MatrixClient"
	_net.time_sync.outbound.random.seed = SEED
	_menu.map_loader.players.snapshots.delay.random.seed = SEED + 1
	_menu.map_loader.players.weapon_presentation.delay.random.seed = SEED + 2
	print("MATRIX READY")
	if game.is_dedicated:
		await _server()
	else:
		await _client()
	await _cleanup()
	quit(1 if _failed else 0)


func _find_actor() -> bool:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		for actor: Node3D in _menu.map_loader.players.actors.values():
			if _net.multiplayer.is_server() or (actor.is_local_player and _net.clock.is_synchronized):
				_actor = actor
		if _actor != null:
			_configure_weapon()
			return true
		await process_frame
	_failed = true
	printerr("MATRIX actor timeout")
	return false


func _configure_weapon() -> void:
	var profile: Resource = _actor.weapon.data.duplicate()
	profile.mag_size = 200
	profile.reserve_mags = 0
	profile.rpm = 300.0
	profile.spread_hip_deg = 0.0
	profile.spread_per_shot_deg = 0.0
	profile.recoil_pattern.clear()
	profile.recoil_fallback_deg = Vector2.ZERO
	profile.recoil_noise_deg = Vector2.ZERO
	_actor.weapon.setup(profile)


func _server() -> void:
	if not await _find_actor():
		return
	_touch("configured")
	if not await _wait_file("sample"):
		return
	# Client has released input and drained the impairment and fire-history windows.
	var combat: Node = _actor.equipment.combat
	var sim: Node = _menu.map_loader.players.snapshots.delay
	print("MATRIX SERVER ", JSON.stringify({"accepted": combat.accepted_shots,
		"rejected_direct": combat.rejected_requests, "pending": _pending_shots(combat),
		"snapshot_drops": sim.dropped, "snapshot_duplicates": sim.duplicated,
		"snapshot_reorders": sim.reordered, "snapshot_overflow": sim.overflowed,
		"server_steps": _actor.server_sim.simulated_ticks}))
	await _wait_file("server.stop")


func _pending_shots(combat: Node) -> int:
	var pending: int = 0
	for frame: RefCounted in combat.history.frames:
		if frame.requested and not frame.consumed:
			pending += 1
	return pending


func _client() -> void:
	var console: RefCounted = load("res://src/ui/debug_console.gd").new()
	console.execute_command("net_sim %s %s %s %s %s" % [_options["--ping"], _options["--loss"],
		_options.get("--jitter", "0"), _options.get("--duplicate", "0"), _options.get("--reorder", "0")])
	_menu.join_button.pressed.emit()
	if not await _find_actor() or not await _wait_file("configured"):
		return
	_actor.local_controller.delay.random.seed = SEED + 3
	_actor.input_reader.yaw = 0.0
	_actor.input_reader.pitch = 0.0
	await create_timer(SETTLE_SECONDS).timeout
	var prediction: RefCounted = _actor.local_controller.prediction
	var before: Dictionary = {"corrections": prediction.reconciliations,
		"samples": prediction.compared_snapshots, "error": prediction.total_error,
		"teleports": prediction.hard_corrections, "misses": prediction.history_misses}
	await _route()
	await create_timer(SETTLE_SECONDS).timeout
	_report_client(prediction, before)
	_touch("sample")
	await _wait_file("client.stop")


func _route() -> void:
	var start: Vector3 = _actor.position
	var previous: Vector3 = start
	var started: int = Time.get_ticks_msec()
	Input.action_press("move_right")
	Input.action_press("fire")
	for tick: int in range(ROUTE_TICKS):
		if tick == ROUTE_TICKS / 2:
			Input.action_release("move_right")
			Input.action_press("move_left")
		await physics_frame
		await process_frame
		_route_distance += previous.distance_to(_actor.position)
		_route_peak = maxf(_route_peak, start.distance_to(_actor.position))
		previous = _actor.position
	Input.action_release("move_right")
	Input.action_release("move_left")
	Input.action_release("fire")
	_route_ms = Time.get_ticks_msec() - started


func _report_client(prediction: RefCounted, before: Dictionary) -> void:
	var samples: int = prediction.compared_snapshots - int(before["samples"])
	var sim: Node = _actor.local_controller.delay
	print("MATRIX CLIENT ", JSON.stringify({"reconciliations": prediction.reconciliations - int(before["corrections"]),
		"route_distance_m": _route_distance, "route_peak_m": _route_peak, "route_ms": _route_ms,
		"samples": samples, "mean_error_m": (prediction.total_error - float(before["error"])) / maxi(1, samples),
		"teleports": prediction.hard_corrections - int(before["teleports"]),
		"history_misses": prediction.history_misses - int(before["misses"]),
		"requests": _actor.equipment.combat.sent_requests, "ping_ms": _net.clock.rtt_seconds * 1000.0,
		"input_drops": sim.dropped, "input_duplicates": sim.duplicated,
		"input_reorders": sim.reordered, "input_overflow": sim.overflowed,
		"server_steps": _actor.server_sim.simulated_ticks}))


func _wait_file(name: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while not FileAccess.file_exists(_options["--directory"].path_join(name)):
		if Time.get_ticks_msec() >= deadline:
			_failed = true
			printerr("MATRIX timeout: ", name)
			return false
		await create_timer(0.02).timeout
	return true


func _touch(name: String) -> void:
	FileAccess.open(_options["--directory"].path_join(name), FileAccess.WRITE).close()


func _cleanup() -> void:
	Input.action_release("move_right")
	Input.action_release("move_left")
	Input.action_release("fire")
	if is_instance_valid(_actor) and _actor.is_local_player:
		_actor.local_controller.enabled = false
		_actor.local_controller.delay.clear()
	_menu.map_loader.players.snapshots.set_physics_process(false)
	_menu.map_loader.players.snapshots.delay.clear()
	_net.time_sync.stop()
	await create_timer(0.25).timeout
	_net.disconnect_all()
	await process_frame
	print("MATRIX CLEANUP actors=", _menu.map_loader.players.actors.size())
