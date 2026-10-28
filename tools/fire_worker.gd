# Real ENet acceptance: production menu, owner input, server traces and HUD sync.
extends SceneTree

const TIMEOUT_MS: int = 20000
const PHASE_SECONDS: float = 1.5
var _options: Dictionary[String, String] = {}
var _net: Node
var _menu: Control
var _local: Node3D
var _target: Node3D
var _events: int = 0
var _last_shot: int = -1
var _min_gap: int = 100000
var _wrong_attacker: bool = false
var _wrong_direction: bool = false
var _cheat_input: RefCounted


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.low_processor_usage_mode_sleep_usec = 1000
	for arg: String in OS.get_cmdline_user_args():
		_options[arg.get_slice("=", 0)] = arg.substr(arg.find("=") + 1)
	_net = root.get_node("Net")
	_cheat_input = load("res://src/player/player_input.gd").new()
	var game: Node = root.get_node("Game")
	game.is_dedicated = _options.get("--role", "client") == "dedicated"
	game.server_port = int(_options["--port"])
	_menu = load("res://src/ui/main_menu.tscn").instantiate() as Control
	_menu.name = "MainMenu"
	root.add_child(_menu)
	_menu.port.value = int(_options["--port"])
	_menu.nickname.text = "FireClient"
	if not game.is_dedicated:
		_menu.join_button.pressed.emit()
	print("FIRE READY")
	if game.is_dedicated:
		await _server()
	else:
		await _client()
	await _cleanup()
	quit()


func _configure(actor: Node3D) -> void:
	var profile: Resource = actor.weapon.data.duplicate()
	profile.mag_size = 3
	profile.reserve_mags = 1
	profile.rpm = 600.0
	profile.reload_time = 0.5
	profile.reload_empty_time = 0.5
	profile.spread_hip_deg = 0.0
	profile.spread_per_shot_deg = 0.0
	profile.spread_move_deg_per_mps = 0.0
	profile.recoil_pattern.clear()
	profile.recoil_fallback_deg = Vector2.ZERO
	profile.recoil_noise_deg = Vector2.ZERO
	actor.weapon.setup(profile)


func _server() -> void:
	await _find_owner(false)
	if _local == null:
		printerr("FIRE server owner timeout")
		return
	_configure(_local)
	_target = load("res://src/maps/testbed/target_dummy.tscn").instantiate() as Node3D
	_target.max_health = 10000.0
	_menu.map_loader.current_map.add_child(_target)
	_target.health_component.reset()
	_target.global_position = _local.global_position + Vector3(0.0, 0.0, -10.0)
	_local.weapon_hitscan.damage_applied.connect(_damaged)
	_local.weapon_hitscan.shot_traced.connect(_traced)
	_local.equipment.combat.fire_accepted.connect(_accepted)
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(_options["--server-stop"]):
		await create_timer(0.02).timeout
	print("FIRE SERVER ", JSON.stringify({"shots": _local.equipment.combat.accepted_shots,
		"rejected": _local.equipment.combat.rejected_requests, "events": _events,
		"health": _target.health_component.current, "min_gap": _min_gap,
		"wrong_attacker": _wrong_attacker, "wrong_direction": _wrong_direction,
		"magazine": _local.weapon.ammo_in_mag, "reserve": _local.weapon.reserve_ammo}))
	print("FIRE SERVER DONE")
	while not FileAccess.file_exists(_options["--server-exit"]):
		await create_timer(0.02).timeout


func _damaged(event: RefCounted) -> void:
	_events += 1
	_wrong_attacker = _wrong_attacker or event.attacker != _local.network_owner_id
	print("FIRE DAMAGE ", JSON.stringify({"damage": event.damage, "attacker": event.attacker,
		"target": str(event.target.get_path())}))


func _traced(_tick: int, _pellet: int, direction: Vector3, _hit: RefCounted) -> void:
	_wrong_direction = _wrong_direction or direction.distance_to(Vector3.FORWARD) > 0.001


func _accepted(_input_tick: int, server_tick: int) -> void:
	if _last_shot >= 0:
		_min_gap = mini(_min_gap, server_tick - _last_shot)
	_last_shot = server_tick


func _client() -> void:
	if _options.has("--ping"):
		var console: RefCounted = load("res://src/ui/debug_console.gd").new()
		console.execute_command("net_sim " + _options["--ping"] + " 2")
	await _find_owner(true)
	if _local == null:
		printerr("FIRE client owner timeout")
		return
	_configure(_local)
	_local.input_reader.yaw = 0.0
	_local.input_reader.pitch = 0.0
	await create_timer(0.7).timeout
	var health: float = _local.health_component.current
	_local.health_component.apply_damage(99.0)
	await _fire_phase()
	print("FIRE FIRST EMPTY ", _local.local_controller.hud.current_ammo)
	Input.action_press("reload")
	await create_timer(0.1).timeout
	Input.action_release("reload")
	await create_timer(0.8).timeout
	await _fire_phase()
	await create_timer(0.3).timeout
	print("FIRE CLIENT ", JSON.stringify({"magazine": _local.weapon.ammo_in_mag,
		"reserve": _local.weapon.reserve_ammo, "hud": _local.local_controller.hud.current_ammo,
		"health_unchanged": health == _local.health_component.current,
		"effects": _local.equipment.effects.shots_presented,
		"requests": _local.equipment.combat.sent_requests,
		"server_steps": _local.server_sim.simulated_ticks}))
	print("FIRE CLIENT DONE")
	while not FileAccess.file_exists(_options["--client-stop"]):
		await create_timer(0.02).timeout


func _fire_phase() -> void:
	Input.action_press("fire")
	var deadline: int = Time.get_ticks_msec() + int(PHASE_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		await process_frame
		if _options.get("--cheat", "false") == "true":
			_local.weapon.ammo_in_mag = 999
			_local.weapon.reserve_ammo = 999
			_local.weapon.next_fire_tick = 0
			_local.weapon.state = 0
			_local.local_controller.history.latest_into(_cheat_input)
			var tick: int = _cheat_input.tick
			var seed: int = load("res://src/net/fire_history.gd").shot_seed(tick, _local.network_owner_id)
			_local.equipment.combat.fire.rpc_id(1, tick, seed)
			_local.equipment.combat.fire.rpc_id(1, tick, seed)
			_local.equipment.combat.fire.rpc_id(1, tick + 10000, seed)
	Input.action_release("fire")


func _find_owner(client: bool) -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		for actor: Node3D in _menu.map_loader.players.actors.values():
			if (not client or actor.is_local_player) and (not client or _net.clock.is_synchronized):
				_local = actor
		if _local != null:
			return
		await process_frame


func _cleanup() -> void:
	Input.action_release("fire")
	Input.action_release("reload")
	if _local != null and _local.is_local_player:
		_local.local_controller.enabled = false
		_local.local_controller.delay.clear()
	_menu.map_loader.players.snapshots.set_physics_process(false)
	_menu.map_loader.players.snapshots.delay.clear()
	_net.time_sync.stop()
	await create_timer(0.15).timeout
	_net.disconnect_all()
	await process_frame
	print("FIRE CLEANUP actors=", _menu.map_loader.players.actors.size())
