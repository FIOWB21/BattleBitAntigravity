# Настоящий полигон, непрерывный ввод, перегрев и охлаждение с реальной геометрией.
extends SceneTree

var _lab: Node3D
var _ok: bool = true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_lab = load("res://src/gadgets/scenes/engineer_lab.tscn").instantiate() as Node3D
	root.add_child(_lab)
	_freeze(_lab)
	var player: CharacterBody3D = _lab.player
	player.release_mouse()
	await physics_frame
	await physics_frame
	await _repair(player)
	print("REPAIR TOOL ACCEPTANCE ", "OK" if _ok else "FAIL")
	_lab.queue_free()
	await process_frame
	quit(0 if _ok else 1)


func _repair(player: CharacterBody3D) -> void:
	var inp: RefCounted = load("res://src/player/player_input.gd").new()
	inp.weapon_slot = 3
	for tick: int in range(1, 65):
		inp.tick = tick
		player.inventory.simulate(inp)
		player.equipment.gadgets.simulate(inp)
	var fixture: Node3D = _lab.get_node("RepairTarget") as Node3D
	var tool: Node3D = player.equipment.gadgets.tool_at(3)
	var count: int = get_node_count()
	inp.buttons = 16
	for tick: int in range(65, 125):
		inp.tick = tick
		player.equipment.gadgets.simulate(inp)
	_ok = _ok and is_equal_approx(fixture.health.current, 325.0)
	print("REPAIR: 1 s health=", fixture.health.current, " heat=", tool.heat)
	await _capture("working", player)
	for tick: int in range(125, 305):
		inp.tick = tick
		player.equipment.gadgets.simulate(inp)
	_ok = _ok and tool.overheated and is_equal_approx(fixture.health.current, 400.0)
	print("REPAIR: 4 s health=", fixture.health.current, " overheated=", tool.overheated)
	await _capture("overheated", player)
	for tick: int in range(305, 500):
		inp.tick = tick
		player.equipment.gadgets.simulate(inp)
	_ok = _ok and not tool.overheated and get_node_count() == count
	print("REPAIR: cooled to=", tool.heat, " stable_nodes=", get_node_count() == count)


func _capture(label: String, player: CharacterBody3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	player.update_camera_visuals(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/repair_tool_" + label + ".png")


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_freeze(child)
