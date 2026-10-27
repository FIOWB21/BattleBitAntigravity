# Настоящий полигон: размещение через PlayerInput, взведение и командный взрыв.
extends SceneTree

var _ok: bool = true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for id: String in ["mine", "c4"]:
		await _check(id)
	await create_timer(0.2).timeout
	print("CHARGES ACCEPTANCE ", "OK" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check(id: String) -> void:
	var lab: Node3D = load("res://src/gadgets/scenes/" + id + "_lab.tscn").instantiate() as Node3D
	root.add_child(lab)
	_freeze(lab)
	var player: CharacterBody3D = lab.player
	player.release_mouse()
	var placed: Array[Node3D] = []
	player.equipment.gadgets.gadget_at(3).deployable_created.connect(
		func(object: Node3D) -> void: placed.append(object))
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
	_ok = _ok and placed.size() == 1
	if placed.size() == 1:
		placed[0].set_physics_process(false)
		placed[0].step(1.0)
		await _capture(id, player)
		var target: Node3D = lab.get_node("VehicleTarget") as Node3D
		var before: float = target.health.current
		inp.tick = 66
		inp.buttons = 32
		player.equipment.gadgets.simulate(inp)
		_ok = _ok and target.health.current < before
		print("CHARGE ", id, ": placed=", placed.size(), " vehicle_hp=", before, " -> ", target.health.current)
	lab.queue_free()
	await process_frame


func _capture(id: String, player: CharacterBody3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	player.input_reader.pitch = -0.6
	player.update_camera_visuals(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/charge_" + id + ".png")


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_freeze(child)
