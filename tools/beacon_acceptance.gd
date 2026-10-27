# Размещение и выбор маяка через существующий экран жизненного цикла.
extends SceneTree

var _lab: Node3D
var _ok: bool = true
var _beacon: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_lab = load("res://src/gadgets/scenes/recon_beacon_lab.tscn").instantiate() as Node3D
	root.add_child(_lab)
	_freeze(_lab)
	var player: CharacterBody3D = _lab.player
	player.release_mouse()
	await physics_frame
	await physics_frame
	_deploy(player)
	await physics_frame
	await physics_frame
	_ok = _ok and is_instance_valid(_beacon)
	if is_instance_valid(_beacon):
		await _exercise(player)
	_lab.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("BEACON ACCEPTANCE ", "OK" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _deploy(player: CharacterBody3D) -> void:
	player.equipment.gadgets.gadget_at(3).deployable_created.connect(
		func(object: Node3D) -> void: _beacon = object)
	var inp: RefCounted = load("res://src/player/player_input.gd").new()
	inp.weapon_slot = 3
	for tick: int in range(1, 65):
		inp.tick = tick
		player.inventory.simulate(inp)
		player.equipment.gadgets.simulate(inp)
	inp.tick = 65
	inp.buttons = 16
	player.equipment.gadgets.simulate(inp)


func _exercise(player: CharacterBody3D) -> void:
	player.input_reader.pitch = -0.5
	await _capture("placed", player)
	player.health_component.apply_damage(1000.0)
	player.health_component.apply_damage(1.0)
	await _capture("spawn_select", player)
	player.life.view.beacon_button.pressed.emit()
	_ok = _ok and player.life.state == 0 and player.health_component.current == 100.0
	_ok = _ok and player.global_position.distance_to(_beacon.global_position) < 2.0
	print("BEACON: button spawned at ", player.global_position, " health=", player.health_component.current)
	await _capture("spawned", player)
	_beacon.health.apply_damage(100.0, 77)
	_ok = _ok and _beacon.is_queued_for_deletion()
	player.health_component.apply_damage(1000.0)
	player.health_component.apply_damage(1.0)
	_ok = _ok and not player.life.select_beacon_spawn()
	print("BEACON: destroyed beacon rejects subsequent respawn=", player.life.state == 3)


func _capture(label: String, player: CharacterBody3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	player.update_camera_visuals(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/beacon_" + label + ".png")


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_freeze(child)
