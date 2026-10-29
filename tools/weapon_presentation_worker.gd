# Real ENet public-state/shot acceptance, with an observer joining during reload.
extends SceneTree

const TIMEOUT_MS: int = 22000
var _options: Dictionary[String, String] = {}
var _net: Node
var _menu: Control
var _shooter: Node3D
var _local: Node3D
var _seen: Dictionary[String, bool] = {}
var _events: int = 0
var _ammo_syncs: int = 0
var _initial_ammo: int = 0
var _initial_reserve: int = 0
var _captured_shot: bool = false
var _captured_reload: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.low_processor_usage_mode_sleep_usec = 1000
	for arg: String in OS.get_cmdline_user_args():
		_options[arg.get_slice("=", 0)] = arg.substr(arg.find("=") + 1)
	_net = root.get_node("Net")
	_open_menu()
	await _find_actors()
	if _shooter == null:
		quit(1)
		return
	_menu.map_loader.players.weapon_presentation.shot_presented.connect(_shot)
	_shooter.equipment.combat.ammo_synchronized.connect(_ammo)
	await _observer_ready()
	if _options.get("--role", "client") == "client":
		await _client()
	else:
		await _server()
	await _wait_file(_options["--stop"])
	await _cleanup()
	quit()


func _open_menu() -> void:
	var game: Node = root.get_node("Game")
	game.is_dedicated = _options.get("--role", "client") == "dedicated"
	game.server_port = int(_options["--port"])
	_menu = load("res://src/ui/main_menu.tscn").instantiate() as Control
	_menu.name = "MainMenu"
	root.add_child(_menu)
	_menu.port.value = int(_options["--port"])
	_menu.nickname.text = _options.get("--nick", "Observer")
	if _options.get("--role", "client") == "listen":
		_menu.host_button.pressed.emit()
	elif not game.is_dedicated:
		_menu.join_button.pressed.emit()
	print("WEAPON READY")


func _observer_ready() -> void:
	if _options.get("--role", "client") != "client" or _options.get("--nick", "") != "Observer":
		return
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	FileAccess.open(_options["--report"] + ".observer_ready", FileAccess.WRITE).close()


func _find_actors() -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		for actor: Node3D in _menu.map_loader.players.actors.values():
			if _net.nicknames.get(actor.network_owner_id, "") == "Shooter":
				_shooter = actor
			if actor.is_local_player:
				_local = actor
		if _menu.map_loader.players.actors.size() >= 2 and _shooter != null \
				and (_local != null or root.get_node("Game").is_dedicated):
			break
		await create_timer(0.02).timeout
	if _shooter == null:
		printerr("WEAPON actor timeout")
		return
	_initial_ammo = _shooter.weapon.ammo_in_mag
	_initial_reserve = _shooter.weapon.reserve_ammo
	if _local != null:
		_local.local_controller.enabled = false
		_local.set_process(false)
		_local.camera.global_position = Vector3(62.0, 1.6, 48.0)
		_local.camera.look_at(Vector3(60.0, 1.2, 50.0))


func _server() -> void:
	if root.get_node("Game").is_dedicated:
		await _wait_file(_options["--report"] + ".observer_ready")
	for actor: Node3D in _menu.map_loader.players.actors.values():
		actor.set_physics_process(false)
	_shooter.global_position = Vector3(60.0, 0.02, 50.0)
	_shooter.global_rotation = Vector3.ZERO
	_shooter.weapon.ammo_in_mag = 7
	_shooter.weapon.reserve_ammo = 71
	await _observe_for(0.6)
	for index: int in range(3):
		_fire()
		await _observe_for(0.2)
	var input: RefCounted = load("res://src/player/player_input.gd").new()
	input.tick = _net.tick
	input.buttons = input.BTN_RELOAD
	_shooter.weapon.simulate(input)
	print("WEAPON RELOAD")
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while _menu.map_loader.players.actors.size() < 3 and Time.get_ticks_msec() < deadline:
		await _observe_for(0.02)
	_shooter.stance = 1
	_shooter.ads.target = 1.0
	_shooter.head.rotation.x = -0.2
	await _observe_for(0.6)
	await _capture("reload_aim_crouch")
	await _observe_for(_shooter.weapon.data.reload_time)
	input.tick = _net.tick
	input.buttons = 0
	_shooter.weapon.simulate(input)
	await _observe_for(0.3)
	_select_pistol()
	await _observe_for(0.4)
	_fire()
	await _observe_for(0.4)
	await _capture("pistol")
	FileAccess.open(_options["--report"], FileAccess.WRITE).close()
	if _local != null:
		_report()
	print("WEAPON SERVER DONE")


func _select_pistol() -> void:
	_shooter.inventory.active_slot = 2
	_shooter.inventory.active_slot_changed.emit(2, _shooter.inventory.weapon_at(2))
	_shooter.weapon.setup(_shooter.weapon.data)
	_shooter.weapon.ammo_in_mag = 3
	_shooter.weapon.reserve_ammo = 17


func _fire() -> void:
	var input: RefCounted = load("res://src/player/player_input.gd").new()
	input.tick = _net.tick
	_shooter.weapon.simulate(input)
	var aim: Transform3D = Transform3D(Basis.IDENTITY, _shooter.head.global_position)
	if not _shooter.weapon_hitscan.fire_requested(_net.tick, 1, aim, 0.0):
		printerr("WEAPON rejected acceptance shot")


func _client() -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while not FileAccess.file_exists(_options["--report"]) and Time.get_ticks_msec() < deadline:
		await _observe_for(0.02)
	if not FileAccess.file_exists(_options["--report"]):
		printerr("WEAPON report timeout")
	await _observe_for(0.25)
	await _capture("final")
	_report()


func _observe_for(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + ceili(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		_observe()
		await process_frame


func _observe() -> void:
	if _shooter == _local or root.multiplayer.is_server() and root.get_node("Game").is_dedicated:
		return
	var view: Node3D = _shooter.remote_view.weapon_view
	if view == null:
		return
	_seen["rifle"] = _seen.get("rifle", false) or view.weapon_id == _shooter.inventory.weapon_at(1).data.id.hash() & 0xffffffff
	_seen["pistol"] = _seen.get("pistol", false) or view.weapon_id == _shooter.inventory.weapon_at(2).data.id.hash() & 0xffffffff
	_seen["reload"] = _seen.get("reload", false) or view.is_reloading and view.model != null and view.model.rotation.length() > 0.1
	_seen["aim"] = _seen.get("aim", false) or view.is_aiming
	_seen["pitch"] = _seen.get("pitch", false) or absf(view.rotation.x + 0.2) < 0.001
	_seen["crouch"] = _seen.get("crouch", false) or _shooter.remote_view.flags & 3 == 1
	_seen["foreign_state"] = _seen.get("foreign_state", false) or _shooter.weapon.state != 0
	if not _captured_reload and _seen.get("reload", false) and view.is_aiming and (_shooter.remote_view.flags & 3) == 1:
		_captured_reload = true
		_capture.call_deferred("reload_aim_crouch")


func _shot(_peer_id: int, _tick: int, _weapon_id: int) -> void:
	_events += 1
	if not _captured_shot:
		_captured_shot = true
		_capture.call_deferred("shot")


func _ammo(_magazine: int, _reserve: int) -> void:
	_ammo_syncs += 1


func _report() -> void:
	print("WEAPON RESULT ", JSON.stringify({"nickname": _options.get("--nick", "Observer"),
		"seen": _seen, "events": _events, "ammo_syncs": _ammo_syncs,
		"foreign_ammo_unchanged": _shooter.weapon.ammo_in_mag == _initial_ammo and _shooter.weapon.reserve_ammo == _initial_reserve,
		"own_magazine": _local.weapon.ammo_in_mag, "own_reserve": _local.weapon.reserve_ammo,
		"hud_magazine": _local.local_controller.hud.current_ammo,
		"actors": _menu.map_loader.players.actors.size()}))
	print("WEAPON CLIENT DONE")


func _wait_file(path: String) -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	if not FileAccess.file_exists(path):
		printerr("WEAPON stop timeout")


func _capture(label: String) -> void:
	if not _options.has("--screens") or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_save_image(label)
	if label == "shot":
		await RenderingServer.frame_post_draw
		_save_image("shot_particles")


func _save_image(label: String) -> void:
	root.get_texture().get_image().save_png(_options["--screens"].path_join(
		_options.get("--nick", "Observer") + "_" + label + ".png"))


func _cleanup() -> void:
	_menu.map_loader.players.snapshots.set_physics_process(false)
	_menu.map_loader.players.snapshots.delay.clear()
	_menu.map_loader.players.lag_compensator.set_physics_process(false)
	_net.time_sync.stop()
	await create_timer(0.15).timeout
	_net.disconnect_all()
	await process_frame
	print("WEAPON CLEANUP actors=", _menu.map_loader.players.actors.size())
