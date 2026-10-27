# Полигон Assault: настоящий слот, контактная граната, штатный урон/эффекты и R.
extends SceneTree

var _lab: Node3D
var _ok: bool = true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_lab = load("res://src/gadgets/scenes/assault_launcher_lab.tscn").instantiate() as Node3D
	root.add_child(_lab)
	_freeze(_lab)
	var player: CharacterBody3D = _lab.player
	player.release_mouse()
	var target: Node3D = load("res://src/gadgets/scenes/spot_fixture.tscn").instantiate() as Node3D
	_lab.add_child(target)
	target.global_position = player.global_position + Vector3(0, 0, -8)
	await physics_frame
	await physics_frame
	await _exercise(player, target)
	_lab.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("GADGET LAUNCHER ACCEPTANCE ", "OK" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _exercise(player: CharacterBody3D, target: Node3D) -> void:
	var primary: Node3D = player.inventory.weapon_at(1)
	var before: int = primary.ammo_in_mag
	var grenades: int = player.equipment.projectiles.grenades
	var inp: RefCounted = load("res://src/player/player_input.gd").new()
	inp.weapon_slot = 3
	for tick: int in range(1, 65):
		inp.tick = tick
		player.inventory.simulate(inp)
		player.equipment.gadgets.simulate(inp)
	var count: int = get_node_count()
	inp.tick = 65
	inp.buttons = 16
	player.equipment.gadgets.simulate(inp)
	_ok = _ok and target.get_node("Health").current == 100.0
	await _flight(player)
	_ok = _ok and target.get_node("Health").is_dead and get_node_count() == count
	_ok = _ok and primary.ammo_in_mag == before and player.equipment.projectiles.grenades == grenades
	print("UNDERBARREL: contact target HP=", target.get_node("Health").current,
		" rifle ammo=", before, " -> ", primary.ammo_in_mag, " grenades=", grenades, " stable_nodes=", get_node_count() == count)
	inp.tick = 66
	inp.buttons = 64
	player.equipment.gadgets.simulate(inp)
	inp.tick = 245
	inp.buttons = 0
	player.equipment.gadgets.simulate(inp)
	_ok = _ok and player.equipment.gadgets.gadget_at(3).charges == 0
	inp.tick = 246
	player.equipment.gadgets.simulate(inp)
	_ok = _ok and player.equipment.gadgets.gadget_at(3).charges == 1
	await _capture("reloaded", player)
	print("UNDERBARREL: reload exactly 180 ticks, charges=", player.equipment.gadgets.gadget_at(3).charges)


func _flight(player: CharacterBody3D) -> void:
	for frame: int in range(15):
		player.equipment.projectiles.system.advance(1.0 / 60.0)
		player.equipment.projectiles.effects.advance(1.0 / 60.0)
		if frame == 2:
			await _capture("flight", player)
		if frame == 9:
			await _capture("explosion", player)


func _capture(label: String, player: CharacterBody3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	player.update_camera_visuals(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/underbarrel_" + label + ".png")


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_freeze(child)
