# Деплой Support, снабжение реального комплекта и замена через перезарядку Gadget.
extends SceneTree

var _lab: Node3D
var _crate: Node3D
var _ok: bool = true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_lab = load("res://src/gadgets/scenes/support_lab.tscn").instantiate() as Node3D
	root.add_child(_lab)
	_freeze(_lab)
	var player: CharacterBody3D = _lab.player
	player.release_mouse()
	player.equipment.gadgets.gadget_at(3).deployable_created.connect(_on_deployed)
	await physics_frame
	await physics_frame
	var inp: RefCounted = load("res://src/player/player_input.gd").new()
	inp.weapon_slot = 3
	for tick: int in range(1, 65):
		inp.tick = tick
		player.inventory.simulate(inp)
		player.equipment.gadgets.simulate(inp)
	inp.tick = 65
	inp.buttons = 16
	player.equipment.gadgets.simulate(inp)
	if _crate == null:
		printerr("AMMO CRATE ACCEPTANCE FAIL: deployment")
		quit(1)
		return
	await _supply(player)
	await _replace(player, inp)
	print("AMMO CRATE ACCEPTANCE ", "OK" if _ok else "FAIL", " | one active crate per entity | magazines unchanged")
	_lab.queue_free()
	await process_frame
	quit(0 if _ok else 1)


func _supply(player: CharacterBody3D) -> void:
	var primary: Node3D = player.inventory.weapon_at(1)
	var secondary: Node3D = player.inventory.weapon_at(2)
	var magazine: int = primary.ammo_in_mag
	primary.reserve_ammo = 0
	secondary.reserve_ammo = 0
	player.equipment.projectiles.grenades = 0
	for frame: int in range(4):
		await physics_frame
	_crate.step(1.0)
	_ok = _ok and primary.reserve_ammo == floori(primary.reserve_capacity() * 0.2)
	_ok = _ok and secondary.reserve_ammo > 0 and player.equipment.projectiles.grenades == 1
	_ok = _ok and primary.ammo_in_mag == magazine
	print("AMMO CRATE: primary=", primary.reserve_ammo, " secondary=", secondary.reserve_ammo,
		" grenades=", player.equipment.projectiles.grenades, " owner=", _crate.owner_id)
	if DisplayServer.get_name() != "headless":
		player.input_reader.pitch = -0.65
		player.update_camera_visuals(0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/ammo_crate_acceptance.png")


func _replace(player: CharacterBody3D, inp: RefCounted) -> void:
	var previous: Node3D = _crate
	var count: int = get_node_count()
	inp.tick = 66
	inp.buttons = 64
	player.equipment.gadgets.simulate(inp)
	inp.tick = 666
	inp.buttons = 0
	player.equipment.gadgets.simulate(inp)
	inp.tick = 667
	inp.buttons = 16
	player.equipment.gadgets.simulate(inp)
	_ok = _ok and _crate != previous and previous.is_queued_for_deletion()
	_ok = _ok and _crate.owner_id == player.get_instance_id()
	await process_frame
	_ok = _ok and get_node_count() == count


func _on_deployed(object: Node3D) -> void:
	_crate = object
	_crate.set_physics_process(false)


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_freeze(child)
