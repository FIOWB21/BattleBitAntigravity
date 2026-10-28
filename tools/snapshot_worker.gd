# Real production ENet traffic. ENet host counters measure UDP payload, including RPC/ENet.
extends SceneTree

const MEASURE_SECONDS: float = 4.0
const TIMEOUT_MS: int = 20000
const IPV4_UDP_BYTES: int = 28
const WARMUP_SECONDS: float = 5.0
var _options: Dictionary[String, String] = {}
var _net: Node
var _menu: Control
var _stream: Node
var _local: Node3D
var _trace: PlayerSnapshot = PlayerSnapshot.new()
var _frames: int = 0
var _first_tick: int = 0
var _last_tick: int = 0
var _cadence_errors: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.low_processor_usage_mode_sleep_usec = 1000
	for arg: String in OS.get_cmdline_user_args():
		_options[arg.get_slice("=", 0)] = arg.substr(arg.find("=") + 1)
	_net = root.get_node("Net")
	var game: Node = root.get_node("Game")
	var role: String = _options.get("--role", "client")
	game.is_dedicated = role == "dedicated"
	game.server_port = int(_options["--port"])
	_menu = load("res://src/ui/main_menu.tscn").instantiate() as Control
	_menu.name = "MainMenu"
	root.add_child(_menu)
	_stream = _menu.map_loader.players.snapshots
	_menu.port.value = int(_options["--port"])
	_menu.nickname.text = _options.get("--nickname", "SnapshotHost")
	if role == "host":
		_menu.host_button.pressed.emit()
	elif role == "client":
		_menu.join_button.pressed.emit()
	print("SNAP READY")
	if role == "client":
		await _client()
	else:
		_stream.snapshot_sent.connect(_server_sample)
		await _server()
	await _cleanup()
	quit()


func _server() -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(_options["--stop-file"]):
		if FileAccess.file_exists(_options["--pause-file"]):
			_stream.set_physics_process(false)
		await create_timer(0.02).timeout


func _server_sample(tick: int, count: int) -> void:
	if count != int(_options["--players"]):
		return
	if _frames == 0:
		_first_tick = tick
	elif tick - _last_tick != 2:
		_cadence_errors += 1
	_frames += 1
	_last_tick = tick
	if tick % 10 != 0:
		return
	for actor: Node3D in _menu.map_loader.players.actors.values():
		print("SNAP SERVER ", JSON.stringify({"tick": tick, "id": actor.network_owner_id,
			"pos": var_to_str(actor.global_position), "velocity": var_to_str(actor.velocity),
			"yaw": actor.global_rotation.y, "pitch": actor.head.rotation.x, "stance": actor.stance,
			"ack": actor.server_sim.input_queue.last_input_tick}))


func _client() -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		if _menu.map_loader.players.actors.size() == int(_options["--players"]) \
				and _net.clock.is_synchronized and _stream.received_packets >= 10:
			break
		await process_frame
	for actor: Node3D in _menu.map_loader.players.actors.values():
		if actor.is_local_player:
			_local = actor
	if _local == null:
		printerr("SNAP actor timeout")
		return
	_stream.snapshot_received.connect(_client_sample)
	_local.input_reader.yaw = deg_to_rad(179.0)
	_local.input_reader.pitch = 0.25
	Input.action_press("move_right")
	Input.action_press("crouch")
	var start: Vector3 = _local.position
	# Let ENet's startup RTT/throttle settle before measuring a sustained stream.
	await create_timer(WARMUP_SECONDS).timeout
	await _measure(start)
	await _freeze()
	await _capture()
	print("SNAP DONE")
	while not FileAccess.file_exists(_options["--stop-file"]) and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout


func _measure(start: Vector3) -> void:
	var host: ENetConnection = (_net.multiplayer.multiplayer_peer as ENetMultiplayerPeer).host
	host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)
	var bytes_before: int = _stream.received_bytes
	var packets_before: int = _stream.received_packets
	var started: int = Time.get_ticks_usec()
	await create_timer(MEASURE_SECONDS * 0.5).timeout
	_local.input_reader.yaw = deg_to_rad(-179.0)
	await create_timer(MEASURE_SECONDS * 0.5).timeout
	var elapsed: float = float(Time.get_ticks_usec() - started) / 1000000.0
	var payload: float = host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	var datagrams: float = host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)
	print("SNAP MEASURE ", JSON.stringify({"players": _menu.map_loader.players.actors.size(),
		"seconds": elapsed, "snapshots": _stream.received_packets - packets_before,
		"snapshot_bytes": _stream.received_bytes - bytes_before, "udp_payload": payload,
		"datagrams": datagrams, "ipv4_bytes_per_second": (payload + datagrams * IPV4_UDP_BYTES) / elapsed,
		"local_unchanged": _local.position == start, "client_steps": _local.server_sim.simulated_ticks,
		"ack": _stream.last_processed_input_tick, "self": _net.multiplayer.get_unique_id()}))


func _client_sample(tick: int, ack: int) -> void:
	if tick % 10 != 0:
		return
	for actor: Node3D in _menu.map_loader.players.actors.values():
		if actor.is_local_player:
			continue
		if not actor.remote_view.interpolator.sample_into(float(tick) + 6.0, _trace):
			continue
		print("SNAP CLIENT ", JSON.stringify({"tick": tick, "id": actor.network_owner_id,
			"pos": var_to_str(_trace.position), "velocity": var_to_str(_trace.velocity),
			"yaw": _trace.yaw, "pitch": _trace.pitch, "flags": _trace.flags,
			"weapon": _trace.weapon_id, "ack": ack}))


func _freeze() -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while not FileAccess.file_exists(_options["--pause-file"]) and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	await create_timer(0.5).timeout
	var poses: Dictionary[int, Vector3] = {}
	for actor: Node3D in _menu.map_loader.players.actors.values():
		if not actor.is_local_player:
			poses[actor.network_owner_id] = actor.remote_view.global_position
	await create_timer(0.3).timeout
	var frozen: bool = not poses.is_empty()
	for actor: Node3D in _menu.map_loader.players.actors.values():
		if poses.has(actor.network_owner_id):
			frozen = frozen and poses[actor.network_owner_id] == actor.remote_view.global_position
	print("SNAP FREEZE ", frozen)


func _capture() -> void:
	if DisplayServer.get_name() == "headless" or not _options.has("--capture"):
		return
	var camera: Camera3D = Camera3D.new()
	_local.get_parent().add_child(camera)
	var center: Vector3 = Vector3.ZERO
	var count: int = 0
	for actor: Node3D in _menu.map_loader.players.actors.values():
		if not actor.is_local_player:
			center += actor.remote_view.global_position
			count += 1
	center /= float(maxi(count, 1))
	camera.global_position = center + Vector3(12.0, 8.0, 16.0)
	camera.look_at(center + Vector3.UP * 0.5)
	camera.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_options["--capture"])
	camera.queue_free()


func _cleanup() -> void:
	if _net.multiplayer.is_server():
		print("SNAP CADENCE ", JSON.stringify({"frames": _frames, "first": _first_tick,
			"last": _last_tick, "errors": _cadence_errors}))
	Input.action_release("move_right")
	Input.action_release("crouch")
	_net.time_sync.stop()
	_stream.set_physics_process(false)
	await create_timer(0.1).timeout
	_net.disconnect_all()
	await process_frame
	print("SNAP CLEANUP ", JSON.stringify({"actors": _menu.map_loader.players.actors.size(),
		"tick": _stream.last_received_tick, "bytes": _stream.received_bytes}))
