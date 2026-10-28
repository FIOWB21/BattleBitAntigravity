# Production map/menu/spawner acceptance in separate Godot processes.
extends SceneTree

const SAMPLE_SECONDS: float = 0.1
const TIMEOUT_SECONDS: float = 25.0
var _options: Dictionary[String, String] = {}
var _menu: Control
var _net: Node
var _captured: bool = false


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
	game.map_id = "testbed" if role != "client" else "client_must_receive_map_id"
	_menu = load("res://src/ui/main_menu.tscn").instantiate() as Control
	_menu.name = "MainMenu"
	root.add_child(_menu)
	_menu.port.value = int(_options["--port"])
	_menu.nickname.text = _options.get("--nickname", "SpawnHost" if role == "host" else "SpawnClient")
	if role == "host":
		_menu.host_button.pressed.emit()
	elif role == "client":
		if _options.has("--skip-ready"):
			_net.connected_to_server.disconnect(_menu.map_loader._on_connected)
		if _options.has("--wrong-ready"):
			_net.connected_to_server.disconnect(_menu.map_loader._on_connected)
			_net.connected_to_server.connect(_wrong_ready)
		if _options.has("--missing-map"):
			_menu.map_loader.maps.clear()
		_menu.join_button.pressed.emit()
	print("SPAWN READY role=", role)
	await _observe()
	_net.disconnect_all()
	await process_frame
	print("SPAWN RESET ", JSON.stringify({"actors": _menu.map_loader.players.actors.size(),
		"map_unloaded": _menu.map_loader.current_map == null, "menu": game.is_in_menu()}))
	quit(0)


func _wrong_ready() -> void:
	_menu.map_loader.load_map("testbed")
	_menu.map_loader.players.map_ready.rpc_id(1, "wrong_map")


func _observe() -> void:
	var deadline: int = Time.get_ticks_msec() + int(float(_options.get("--hold", str(TIMEOUT_SECONDS))) * 1000.0)
	while Time.get_ticks_msec() < deadline:
		_record()
		if _options.has("--stop-file") and FileAccess.file_exists(_options["--stop-file"]):
			break
		if _menu.map_loader.players.actors.size() == 3 and not _captured:
			await _capture()
		await create_timer(SAMPLE_SECONDS).timeout


func _record() -> void:
	var records: Array[Dictionary] = []
	for actor: Node3D in _menu.map_loader.players.actors.values():
		records.append({"id": actor.network_owner_id, "state_authority": actor.get_multiplayer_authority(),
			"input_authority": actor.local_controller.get_multiplayer_authority(),
			"local": actor.is_local_player, "camera": actor.camera.current,
			"hud": actor.local_controller.hud != null, "sim": actor.server_sim.enabled,
			"capsule": actor.remote_view.visible, "position": var_to_str(actor.position),
			"health": actor.health_component.current})
	print("SPAWN SAMPLE ", JSON.stringify({"self": _net.multiplayer.get_unique_id(),
		"map": String(_menu.map_loader.current_data.id) if _menu.map_loader.current_data != null else "",
		"actors": records, "time": Time.get_ticks_msec()}))


func _capture() -> void:
	_captured = true
	if not _options.has("--capture") or DisplayServer.get_name() == "headless":
		return
	var local: Node3D
	var focus: Vector3 = Vector3.ZERO
	for actor: Node3D in _menu.map_loader.players.actors.values():
		if actor.is_local_player:
			local = actor
		else:
			focus += actor.global_position
	if local == null:
		return
	focus /= 2.0
	focus.y = local.global_position.y + local.movement_config.stand_height * 0.5
	var view: Basis = Basis.looking_at(focus - local.camera.global_position)
	local.input_reader.yaw = view.get_euler().y
	local.input_reader.pitch = view.get_euler().x
	await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(_options["--capture"])
	print("SPAWN CAPTURE result=", result)
