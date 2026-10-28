# Real production input RPCs and a same-input local replay, without state replication.
extends SceneTree

const MOVE_TICKS: int = 45
const OBSERVE_TICKS: int = 100
var _options: Dictionary[String, String] = {}
var _menu: Control
var _net: Node
var _references: Array[Node3D] = []
var _max_error: float = 0.0
var _replayed: int = 0
var _local: Node3D
var _start: Vector3


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
	node_added.connect(_track_node)
	_menu = load("res://src/ui/main_menu.tscn").instantiate() as Control
	_menu.name = "MainMenu"
	root.add_child(_menu)
	_menu.port.value = int(_options["--port"])
	_menu.nickname.text = _options.get("--nickname", "InputHost" if _options.get("--role") == "host" else "InputClient")
	if _options.get("--role", "client") == "host":
		_menu.host_button.pressed.emit()
	elif not game.is_dedicated:
		_menu.join_button.pressed.emit()
	print("INPUT READY")
	if _net.multiplayer.is_server():
		await _observe_server()
	else:
		await _drive_client()
	_net.time_sync.stop()
	await create_timer(0.1).timeout
	_net.disconnect_all()
	await process_frame
	for reference: Node3D in _references:
		if is_instance_valid(reference):
			reference.queue_free()
	await process_frame
	print("INPUT CLEANUP actors=", _menu.map_loader.players.actors.size())
	quit(0)


func _track_node(node: Node) -> void:
	if node.has_method("step_simulation") and int(node.get("network_owner_id")) > 0:
		node.ready.connect(_track_actor.bind(node))


func _track_actor(actor: Node3D) -> void:
	if not _net.multiplayer.is_server():
		return
	var reference: Node3D = load("res://src/player/player.tscn").instantiate() as Node3D
	reference.is_local_player = false
	reference.set_physics_process(false)
	reference.transform = actor.transform
	actor.get_parent().add_child.call_deferred(reference)
	_references.append(reference)
	actor.server_sim.input_simulated.connect(_replay.bind(actor, reference))


func _replay(inp: RefCounted, actor: Node3D, reference: Node3D) -> void:
	if not reference.is_inside_tree():
		return
	reference.step_simulation(inp, 1.0 / Engine.physics_ticks_per_second)
	_max_error = maxf(_max_error, (actor.position - reference.position).length())
	_replayed += 1
	if inp.move.length() > 0.0 or actor.server_sim.input_queue.repeated_ticks == 6:
		print("INPUT STEP ", JSON.stringify({"id": actor.network_owner_id,
			"tick": inp.tick, "source": actor.server_sim.input_queue.last_input_tick,
			"move": var_to_str(inp.move), "position": var_to_str(actor.position),
			"repeat": actor.server_sim.input_queue.repeated_ticks, "error": _max_error}))


func _observe_server() -> void:
	var deadline: int = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(_options["--stop-file"]):
		await create_timer(0.03).timeout
	print("INPUT REPLAY ", JSON.stringify({"ticks": _replayed, "max_error": _max_error}))


func _drive_client() -> void:
	var deadline: int = Time.get_ticks_msec() + 10000
	while _local == null and Time.get_ticks_msec() < deadline:
		for actor: Node3D in _menu.map_loader.players.actors.values():
			if actor.is_local_player and _net.clock.is_synchronized:
				_local = actor
		await process_frame
	if _local == null:
		printerr("INPUT actor timeout")
		return
	_start = _local.position
	if _options.has("--attack"):
		_attack()
	Input.action_press("move_right")
	for tick: int in range(MOVE_TICKS):
		await physics_frame
	await process_frame
	# Stop transmission while movement is held to verify five repeats followed by stop.
	_local.local_controller.enabled = false
	Input.action_release("move_right")
	for tick: int in range(OBSERVE_TICKS):
		await physics_frame
	print("INPUT CLIENT ", JSON.stringify({"unchanged": _local.position == _start,
		"simulated": _local.server_sim.simulated_ticks, "sent": _local.input_reader.tick}))


func _attack() -> void:
	var history: RefCounted = load("res://src/net/input_history.gd").new()
	history.configure(_net.config.input_history_count)
	var inp: RefCounted = load("res://src/player/player_input.gd").new()
	inp.tick = _net.tick + 120
	inp.move = Vector2.LEFT
	history.push(inp)
	_local.server_sim.submit_input.rpc_id(1, history.packet)
	history.configure(_net.config.input_history_count)
	inp.tick = _net.tick
	history.push(inp)
	history.packet[0] = 127
	history.packet[1] = 127
	_local.server_sim.submit_input.rpc_id(1, history.packet)
	history.configure(_net.config.input_history_count)
	history.push(inp)
	for actor: Node3D in _menu.map_loader.players.actors.values():
		if actor != _local:
			actor.server_sim.submit_input.rpc_id(1, history.packet)
	print("INPUT ATTACK future diagonal other_owner")
