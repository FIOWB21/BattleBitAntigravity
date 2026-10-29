# Real ENet event acceptance: a server hitscan, three game peers and two respawns.
extends SceneTree

const TIMEOUT_MS: int = 24000
var _options: Dictionary[String, String] = {}
var _net: Node
var _menu: Control
var _local: Node3D
var _victim: Node3D
var _shooter: Node3D
var _deaths: Array[Dictionary] = []
var _hits: Array[Dictionary] = []
var _directions: int = 0
var _spawns: Dictionary[int, int] = {}
var _identities: Dictionary[int, int] = {}
var _saw_damage: bool = false
var _saw_dead: bool = false
var _killcam_dot: float = 1.0
var _protected: bool = true
var _deadline_ticks: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.low_processor_usage_mode_sleep_usec = 1000
	for arg: String in OS.get_cmdline_user_args():
		_options[arg.get_slice("=", 0)] = arg.substr(arg.find("=") + 1)
	_net = root.get_node("Net")
	root.get_node("Events").player_died.connect(_died)
	root.get_node("Events").hit_confirmed.connect(_hit)
	root.get_node("Events").damage_indicated.connect(_damage)
	root.get_node("Events").player_spawned.connect(_spawned)
	var game: Node = root.get_node("Game")
	game.is_dedicated = _options.get("--role", "client") == "dedicated"
	game.server_port = int(_options["--port"])
	_menu = load("res://src/ui/main_menu.tscn").instantiate() as Control
	_menu.name = "MainMenu"
	root.add_child(_menu)
	_menu.port.value = int(_options["--port"])
	_menu.nickname.text = _options.get("--nick", "Alpha")
	if _options.get("--role", "client") == "listen":
		_menu.host_button.pressed.emit()
	elif not game.is_dedicated:
		_menu.join_button.pressed.emit()
	print("COMBAT READY")
	if _options.get("--role", "client") == "client":
		await _client()
	else:
		await _server()
	await _wait_file(_options["--stop"])
	await _cleanup()
	quit()


func _find_actors() -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while _menu.map_loader.players.actors.size() < 3 and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	if _menu.map_loader.players.actors.size() != 3:
		printerr("COMBAT actor timeout")
	for actor: Node3D in _menu.map_loader.players.actors.values():
		_identities[actor.network_owner_id] = actor.get_instance_id()
		var nickname: String = _net.nicknames.get(actor.network_owner_id, "")
		if nickname == "Bravo":
			_victim = actor
		if nickname == "Alpha":
			_shooter = actor
		if actor.is_local_player:
			_local = actor


func _server() -> void:
	await _find_actors()
	if _shooter == null or _victim == null:
		printerr("COMBAT missing server actors")
		return
	if _local != null:
		_local.local_controller.enabled = false
	_victim.life.rules = _victim.life.rules.duplicate()
	_victim.life.rules.downed_enabled = false
	var data: Resource = _shooter.weapon.data.duplicate()
	data.damage_near = 60.0
	data.damage_far = 60.0
	data.recoil_pattern.clear()
	data.recoil_fallback_deg = Vector2.ZERO
	data.recoil_noise_deg = Vector2.ZERO
	_shooter.weapon.setup(data)
	await create_timer(0.8).timeout
	for cycle: int in range(2):
		await _cycle(cycle)
	print("COMBAT SERVER ", JSON.stringify({"protected": _protected, "deadlines": _deadline_ticks,
		"actors": _menu.map_loader.players.actors.size(), "identities": _same_actors(), "deaths": _deaths}))
	if _local != null:
		await _report()
	FileAccess.open(_options["--report"], FileAccess.WRITE).close()
	print("COMBAT SERVER DONE")


func _cycle(cycle: int) -> void:
	_shooter.global_position = Vector3(60.0, 0.02, 60.0)
	_victim.global_position = Vector3(60.0, 0.02, 50.0)
	await create_timer(0.4).timeout
	_victim.health_component.apply_damage(10.0, _shooter.network_owner_id, 1,
		&"sample_ar", _shooter.head.global_position)
	await create_timer(0.15).timeout
	var tick: int = _net.tick
	var aim: Transform3D = Transform3D(Basis.IDENTITY, _shooter.head.global_position)
	if not _shooter.weapon_hitscan.fire_requested(tick, 1, aim, 0.0):
		printerr("COMBAT rejected acceptance hitscan")
	var players: Node = _menu.map_loader.players
	var due: int = players.respawns.deadlines.get(_victim.network_owner_id, -1)
	_deadline_ticks.append(due - tick)
	if _deaths.size() != cycle + 1:
		printerr("COMBAT hitscan did not kill once")
	await create_timer(0.25).timeout
	await _capture("dead_%d" % cycle)
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while _victim.life.state != 0 and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	if _victim.life.state != 0:
		printerr("COMBAT respawn timeout")
	_victim.health_component.apply_damage(1000.0, _shooter.network_owner_id, 0, &"sample_ar")
	_protected = _protected and _victim.health_component.current == 100.0
	await _capture("spawn_%d" % cycle)
	await create_timer(2.1).timeout


func _client() -> void:
	await _find_actors()
	if _local == null:
		printerr("COMBAT missing local actor")
		return
	_local.health_component.health_changed.connect(_health)
	await _wait_file(_options["--report"])
	await create_timer(0.2).timeout
	await _report()


func _died(victim: int, killer: int, weapon: StringName, headshot: bool) -> void:
	_deaths.append({"victim": victim, "killer": killer, "weapon": String(weapon), "headshot": headshot})
	if _local != null and victim == _local.network_owner_id:
		_watch_camera.call_deferred()


func _watch_camera() -> void:
	await process_frame
	await process_frame
	var target: Vector3 = _shooter.remote_view.global_position + Vector3.UP * 1.65
	_killcam_dot = minf(_killcam_dot, (-_local.camera.global_basis.z).dot(
		(target - _local.camera.global_position).normalized()))
	await _capture("victim_dead_%d" % _deaths.size())


func _hit(zone: int, killed: bool) -> void:
	_hits.append({"zone": zone, "killed": killed})


func _damage(_direction: Vector3) -> void:
	_directions += 1


func _spawned(id: int) -> void:
	_spawns[id] = _spawns.get(id, 0) + 1


func _health(current: float, _maximum: float) -> void:
	_saw_damage = _saw_damage or current == 90.0
	_saw_dead = _saw_dead or current == 0.0


func _same_actors() -> bool:
	for id: int in _identities:
		if not _menu.map_loader.players.actors.has(id) \
				or _menu.map_loader.players.actors[id].get_instance_id() != _identities[id]:
			return false
	return true


func _report() -> void:
	await _capture("final")
	print("COMBAT RESULT ", JSON.stringify({"nickname": _options.get("--nick", "Alpha"),
		"deaths": _deaths, "hits": _hits, "directions": _directions,
		"feed": _local.local_controller.hud.combat.feed.lines, "actors": _menu.map_loader.players.actors.size(),
		"identities": _same_actors(), "health": _local.local_controller.hud.current_health,
		"damage": _saw_damage, "dead": _saw_dead, "killcam_dot": _killcam_dot,
		"victim_spawns": _spawns.get(_victim.network_owner_id, 0)}))
	print("COMBAT CLIENT DONE")


func _wait_file(path: String) -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	if not FileAccess.file_exists(path):
		printerr("COMBAT file timeout ", path)


func _capture(label: String) -> void:
	if not _options.has("--screens") or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_options["--screens"].path_join(
		_options.get("--nick", "Alpha") + "_" + label + ".png"))


func _cleanup() -> void:
	if _local != null:
		_local.local_controller.enabled = false
		if _local.local_controller.delay != null:
			_local.local_controller.delay.clear()
	_menu.map_loader.players.snapshots.set_physics_process(false)
	_menu.map_loader.players.snapshots.delay.clear()
	_net.time_sync.stop()
	await create_timer(0.15).timeout
	_net.disconnect_all()
	await process_frame
	print("COMBAT CLEANUP actors=", _menu.map_loader.players.actors.size())
