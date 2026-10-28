# Production ENet/map/input acceptance worker with optional Forward+ capture.
extends SceneTree

const TIMEOUT_MS: int = 20000
const ROUTE_TICKS: int = 360
var _options: Dictionary[String, String] = {}
var _net: Node
var _menu: Control
var _local: Node3D
var _previous: Vector3
var _max_step: float = 0.0
var _backward_steps: int = 0
var _body_backward_steps: int = 0
var _previous_camera: Vector3
var _max_camera_step: float = 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.low_processor_usage_mode_sleep_usec = 1000
	for arg: String in OS.get_cmdline_user_args():
		_options[arg.get_slice("=", 0)] = arg.substr(arg.find("=") + 1)
	_net = root.get_node("Net")
	var game: Node = root.get_node("Game")
	game.is_dedicated = _options.get("--role", "client") == "dedicated"
	game.server_port = int(_options["--port"])
	_menu = load("res://src/ui/main_menu.tscn").instantiate() as Control
	_menu.name = "MainMenu"
	root.add_child(_menu)
	_menu.port.value = int(_options["--port"])
	_menu.nickname.text = "PredictionClient"
	if not game.is_dedicated:
		_menu.join_button.pressed.emit()
	print("PRED READY")
	if game.is_dedicated:
		await _server()
	else:
		await _client()
	await _cleanup()
	quit()


func _server() -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	var shifted: bool = false
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(_options["--stop-file"]):
		if not shifted and _options.has("--shift-file") and FileAccess.file_exists(_options["--shift-file"]):
			for actor: Node3D in _menu.map_loader.players.actors.values():
				actor.position.x += 0.5
				print("PRED SHIFT 0.5")
			shifted = true
		await create_timer(0.02).timeout
	for actor: Node3D in _menu.map_loader.players.actors.values():
		print("PRED SERVER ", JSON.stringify({"position": var_to_str(actor.position),
			"ack": actor.server_sim.input_queue.last_input_tick,
			"steps": actor.server_sim.simulated_ticks}))


func _client() -> void:
	var console: RefCounted = load("res://src/ui/debug_console.gd").new()
	console.execute_command("net_sim " + _options.get("--ping", "120") + " " + _options.get("--loss", "2"))
	await _find_owner()
	if _local == null:
		printerr("PRED owner timeout")
		return
	_local.local_controller.delay.random.seed = 460
	_menu.map_loader.players.snapshots.delay.random.seed = 461
	await create_timer(2.0).timeout
	_local.input_reader.yaw = 0.0
	var start: Vector3 = _local.position
	var ammo: int = _local.weapon.ammo_in_mag
	var prediction: RefCounted = _local.local_controller.prediction
	var before: int = prediction.reconciliations
	var teleports: int = prediction.hard_corrections
	var ack: int = _menu.map_loader.players.snapshots.last_processed_input_tick
	_previous = _local.position
	_previous_camera = _local.camera.global_position
	Input.action_press("move_right")
	await physics_frame
	await process_frame
	print("PRED RESPONSE ", JSON.stringify({"distance": _local.position.distance_to(start),
		"ack_unchanged": ack == _menu.map_loader.players.snapshots.last_processed_input_tick}))
	await _route()
	Input.action_release("move_right")
	await create_timer(0.8).timeout
	_report_result(start, before, teleports, ammo)
	await _capture()
	print("PRED DONE")
	while not FileAccess.file_exists(_options["--client-stop"]):
		await create_timer(0.02).timeout


func _report_result(start: Vector3, before: int, teleports: int, ammo: int) -> void:
	var prediction: RefCounted = _local.local_controller.prediction
	print("PRED RESULT ", JSON.stringify({"distance": _local.position.distance_to(start),
		"reconciliations": prediction.reconciliations - before,
		"teleports": prediction.hard_corrections - teleports, "history_misses": prediction.history_misses,
		"max_step": _max_step, "backward_camera_steps": _backward_steps,
		"body_backward_steps": _body_backward_steps,
		"max_camera_step": _max_camera_step,
		"input_drops": _local.local_controller.delay.dropped,
		"snapshot_drops": _menu.map_loader.players.snapshots.delay.dropped,
		"predicted": prediction.predicted_ticks, "server_steps": _local.server_sim.simulated_ticks,
		"ammo_unchanged": _local.weapon.ammo_in_mag == ammo, "ping": game_ping(),
		"position": var_to_str(_local.position), "offset": prediction.visual_offset.length()}))


func _find_owner() -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		for actor: Node3D in _menu.map_loader.players.actors.values():
			if actor.is_local_player and _net.clock.is_synchronized:
				_local = actor
		if _local != null:
			return
		await process_frame


func _route() -> void:
	for tick: int in range(ROUTE_TICKS):
		if tick == ROUTE_TICKS / 2 and _options.has("--shift-file"):
			FileAccess.open(_options["--shift-file"], FileAccess.WRITE).close()
		await physics_frame
		await process_frame
		var displacement: Vector3 = _local.position - _previous
		var camera_displacement: Vector3 = _local.camera.global_position - _previous_camera
		_max_step = maxf(_max_step, displacement.length())
		_max_camera_step = maxf(_max_camera_step, camera_displacement.length())
		if tick > 30 and displacement.x < -0.02:
			_body_backward_steps += 1
		if tick > 30 and camera_displacement.x < -0.02:
			_backward_steps += 1
		_previous = _local.position
		_previous_camera = _local.camera.global_position


func game_ping() -> float:
	return float(root.get_node("Game").debug.get("ping_ms", 0.0))


func _capture() -> void:
	if DisplayServer.get_name() == "headless" or not _options.has("--capture"):
		return
	_menu.get_node("DebugOverlay").set_overlay_visible(true)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_options["--capture"])


func _cleanup() -> void:
	Input.action_release("move_right")
	if _local != null:
		_local.local_controller.enabled = false
		_local.local_controller.delay.clear()
	_menu.map_loader.players.snapshots.set_physics_process(false)
	_menu.map_loader.players.snapshots.delay.clear()
	_net.time_sync.stop()
	await create_timer(0.15).timeout
	_net.disconnect_all()
	await process_frame
	print("PRED CLEANUP actors=", _menu.map_loader.players.actors.size())
