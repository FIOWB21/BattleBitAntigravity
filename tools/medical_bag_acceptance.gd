# Настоящий полигон, выбор слота через PlayerInput, лечение и точное истечение.
extends SceneTree

var _lab: Node3D
var _bag: Node3D
var _ok: bool = true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_lab = load("res://src/gadgets/scenes/medic_lab.tscn").instantiate() as Node3D
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
	if _bag == null:
		printerr("MEDICAL BAG ACCEPTANCE FAIL: deployment")
		quit(1)
		return
	await _check_healing(player)
	_lab.queue_free()
	await process_frame
	quit(0 if _ok else 1)


func _check_healing(player: CharacterBody3D) -> void:
	player.health_component.apply_damage(60.0)
	for frame: int in range(4):
		await physics_frame
	_bag.step(1.0)
	_ok = _ok and is_equal_approx(player.health_component.current, 50.0)
	print("MEDICAL BAG: deployed=", _bag.global_position, " health_after_1s=", player.health_component.current)
	if DisplayServer.get_name() != "headless":
		player.input_reader.pitch = -0.65
		player.update_camera_visuals(0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/medical_bag_acceptance.png")
	_bag.step(19.0)
	_ok = _ok and _bag.is_queued_for_deletion()
	print("MEDICAL BAG ACCEPTANCE ", "OK" if _ok else "FAIL", " | lifetime=20 s | radius=4 m | heal=10 HP/s")


func _on_deployed(object: Node3D) -> void:
	_bag = object
	_bag.set_physics_process(false)


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_freeze(child)
