# Real ENet/clock/interpolator/input acceptance, with a transverse network player.
extends SceneTree

const TIMEOUT_MS: int = 16000
const FIRE_SECONDS: float = 3.0
var _options: Dictionary[String, String] = {}
var _menu: Control
var _net: Node
var _shooter: Node3D
var _target: Node3D
var _moving: bool = false
var _input: RefCounted
var _history: RefCounted
var _hits: int = 0
var _shots: int = 0
var _max_age: int = 0
var _min_age: int = 10000
var _restored: bool = true
var _aim_samples: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.low_processor_usage_mode_sleep_usec = 1000
	for arg: String in OS.get_cmdline_user_args():
		_options[arg.get_slice("=", 0)] = arg.substr(arg.find("=") + 1)
	_net = root.get_node("Net")
	_menu = load("res://src/ui/main_menu.tscn").instantiate() as Control
	_menu.name = "MainMenu"
	root.add_child(_menu)
	_menu.port.value = int(_options["--port"])
	_menu.nickname.text = "LagTarget" if _server_role() else "LagShooter"
	if _server_role():
		_menu.host_button.pressed.emit()
		await _server()
	else:
		load("res://src/ui/debug_console.gd").new().execute_command("net_sim 150 0")
		_menu.join_button.pressed.emit()
		await _client()
	await _cleanup()
	quit()


func _server_role() -> bool:
	return _options.get("--role", "client") == "server"


func _configure(actor: Node3D) -> void:
	var data: Resource = actor.weapon.data.duplicate()
	data.mag_size = 100
	data.rpm = 240.0
	data.spread_hip_deg = 0.0
	data.spread_per_shot_deg = 0.0
	data.spread_move_deg_per_mps = 0.0
	data.recoil_pattern.clear()
	data.recoil_fallback_deg = Vector2.ZERO
	data.recoil_noise_deg = Vector2.ZERO
	actor.weapon.setup(data)


func _server() -> void:
	_target = _menu.map_loader.players.actors[1]
	_target.local_controller.enabled = false
	_target.global_position = Vector3(60.0, 0.02, 60.0)
	_target.health_component.max_health = 10000.0
	_target.health_component.reset()
	_input = load("res://src/player/player_input.gd").new()
	_history = load("res://src/net/input_history.gd").new()
	_history.configure(6)
	physics_frame.connect(_move_target)
	print("LAG READY")
	await _find_players()
	if _shooter == null:
		return
	_configure(_shooter)
	_shooter.global_position = Vector3(60.0, 0.02, 80.0)
	_shooter.weapon_hitscan.damage_applied.connect(_damaged)
	_shooter.equipment.combat.fire_accepted.connect(_accepted)
	if _options.get("--mode", "normal") == "disabled":
		_shooter.equipment.combat.lag_compensator = null
	_moving = true
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while not FileAccess.file_exists(_path("done")) and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	print("LAG SERVER ", JSON.stringify({"shots": _shots, "hits": _hits,
		"health": _target.health_component.current, "max_age": _max_age,
		"min_age": _min_age, "restored": _restored, "x": _target.position.x}))
	print("LAG SERVER DONE")
	while not FileAccess.file_exists(_path("exit")) and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout


func _move_target() -> void:
	if not _moving:
		return
	_input.tick = _net.tick + 1
	_input.move = Vector2.RIGHT
	_input.yaw = 0.0
	_history.push(_input)
	_target.server_sim.receive_local(_history.packet)


func _damaged(event: RefCounted) -> void:
	if event.target == _target:
		_hits += 1
	_restored = _restored and not _menu.map_loader.players.lag_compensator.active
	for zone: Area3D in _target.hitboxes.get_zones():
		_restored = _restored and PhysicsServer3D.area_get_transform(zone.get_rid()) == zone.global_transform


func _accepted(input_tick: int, tick: int) -> void:
	_shots += 1
	var lag: Node = _menu.map_loader.players.lag_compensator
	if lag.last_rewind_tick >= 0:
		var age: int = tick - lag.last_rewind_tick
		_min_age = mini(_min_age, age)
		_max_age = maxi(_max_age, age)
	print("LAG SHOT ", JSON.stringify({"server": tick, "input": input_tick,
		"view": _shooter.equipment.combat.history.slot(input_tick).view_tick,
		"rewound": lag.last_rewind_tick, "pending": _shooter.server_sim.input_queue.pending_count}))


func _client() -> void:
	await _find_players()
	if _shooter == null or _target == null:
		return
	_configure(_shooter)
	physics_frame.connect(_aim_at_visible_target)
	if _options.get("--mode", "normal") == "forged":
		_shooter.weapon.fired.disconnect(_shooter.equipment.combat._predicted_fire)
		_shooter.weapon.fired.connect(_forged_fire)
	await create_timer(1.5).timeout
	Input.action_press("fire")
	await create_timer(FIRE_SECONDS).timeout
	Input.action_release("fire")
	await create_timer(0.5).timeout
	print("LAG CLIENT ", JSON.stringify({"ping": _net.clock.rtt_seconds * 1000.0,
		"samples": _aim_samples, "view_tick": _shooter.equipment.combat.view_tick(),
		"server_estimate": _net.clock.estimated_server_tick(Time.get_ticks_usec())}))
	FileAccess.open(_path("done"), FileAccess.WRITE).close()
	print("LAG CLIENT DONE")
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while not FileAccess.file_exists(_path("client_stop")) and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout


func _aim_at_visible_target() -> void:
	if not _net.clock.is_synchronized or _target == null:
		return
	var estimate: float = _net.clock.estimated_server_tick(Time.get_ticks_usec())
	if not _target.remote_view.present_at(estimate):
		return
	var point: Vector3 = _target.remote_view.global_position + Vector3.UP
	var direction: Vector3 = point - _shooter.head.global_position
	_shooter.input_reader.yaw = atan2(-direction.x, -direction.z)
	_shooter.input_reader.pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	_aim_samples += 1


func _forged_fire(tick: int) -> void:
	var seed: int = load("res://src/net/fire_history.gd").shot_seed(tick, _shooter.network_owner_id)
	_shooter.equipment.combat.fire.rpc_id(1, tick, seed, -10000)


func _find_players() -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		for actor: Node3D in _menu.map_loader.players.actors.values():
			if actor.network_owner_id == 1:
				_target = actor
			else:
				_shooter = actor
		if _target != null and _shooter != null and (_server_role() or _net.clock.is_synchronized):
			return
		await process_frame
	printerr("LAG timeout finding players")


func _path(suffix: String) -> String:
	return _options["--directory"].path_join(suffix)


func _cleanup() -> void:
	_moving = false
	Input.action_release("fire")
	if _shooter != null and _shooter.is_local_player:
		_shooter.local_controller.enabled = false
		_shooter.local_controller.delay.clear()
	_menu.map_loader.players.snapshots.set_physics_process(false)
	_menu.map_loader.players.snapshots.delay.clear()
	_net.time_sync.stop()
	await create_timer(0.15).timeout
	_net.disconnect_all()
	await process_frame
	print("LAG CLEANUP actors=", _menu.map_loader.players.actors.size(),
		" history=", _menu.map_loader.players.lag_compensator.tracks.size())
