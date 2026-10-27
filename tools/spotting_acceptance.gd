# Приобретение цели настоящим вводом и HUD за настоящей стеной на полигоне.
extends SceneTree

var _lab: Node3D
var _ok: bool = true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_lab = load("res://src/gadgets/scenes/recon_spot_lab.tscn").instantiate() as Node3D
	root.add_child(_lab)
	_freeze(_lab)
	var player: CharacterBody3D = _lab.player
	player.release_mouse()
	await physics_frame
	await physics_frame
	_select_and_spot(player)
	var registry: RefCounted = player.equipment.gadgets.spots
	_ok = _ok and registry.marks[0].remaining == 8.0
	_make_wall()
	await physics_frame
	await physics_frame
	player.equipment.gadgets.markers.update_markers()
	_ok = _ok and player.equipment.gadgets.markers.labels[0].visible
	await _capture("wall", player)
	registry.step(7.99)
	_ok = _ok and registry.marks[0].remaining > 0.0
	registry.step(0.01)
	player.equipment.gadgets.markers.update_markers()
	_ok = _ok and not player.equipment.gadgets.markers.labels[0].visible
	print("SPOTTING: target acquired, allied marker through wall, expires at 8 s; result=", _ok)
	await _capture("expired", player)
	_lab.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("SPOTTING ACCEPTANCE ", "OK" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _select_and_spot(player: CharacterBody3D) -> void:
	var inp: RefCounted = load("res://src/player/player_input.gd").new()
	inp.weapon_slot = 3
	for tick: int in range(1, 65):
		inp.tick = tick
		player.inventory.simulate(inp)
		player.equipment.gadgets.simulate(inp)
	inp.tick = 65
	inp.buttons = 16
	player.equipment.gadgets.simulate(inp)


func _make_wall() -> void:
	var wall: StaticBody3D = StaticBody3D.new()
	wall.position = Vector3(0, 1.5, -1)
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(4, 3, 0.3)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	wall.add_child(collision)
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = shape.size
	var model: MeshInstance3D = MeshInstance3D.new()
	model.mesh = mesh
	wall.add_child(model)
	_lab.add_child(wall)


func _capture(label: String, player: CharacterBody3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	player.update_camera_visuals(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/spot_" + label + ".png")


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_freeze(child)
