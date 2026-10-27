# Приёмка 2.11: реальный полигон, ввод игрока и снимки процедурного удара.
extends SceneTree

const DELTA: float = 1.0 / 60.0

var _world: Node3D
var _player: CharacterBody3D
var _target: TargetDummy
var _tick: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 120
	_setup()
	await physics_frame
	await physics_frame
	var nodes: int = get_node_count()
	var ammo: int = _player.weapon.ammo_in_mag
	await _swing("face")
	var face_ok: bool = _target.health_component.current == 50.0 and not _target.is_dead
	print("ACCEPT 2.11 face: health=", _target.health_component.current, " nodes=", get_node_count())
	_target.rotation.y = 0.0
	_target.health_component.max_health = 500.0
	_target.health_component.reset()
	await physics_frame
	await physics_frame
	await _swing("back")
	var back_ok: bool = _target.is_dead and _target.health_component.current == 0.0
	print("ACCEPT 2.11 back: dead=", _target.is_dead, " health=", _target.health_component.current)
	var success: bool = face_ok and back_ok and get_node_count() == nodes
	success = success and _player.weapon.ammo_in_mag == ammo and not _player.equipment.melee.busy
	print("ACCEPT 2.11: nodes=", nodes, " -> ", get_node_count(), " ammo=", ammo,
		" -> ", _player.weapon.ammo_in_mag, " cosmetic_pose=", _player.equipment.melee_view.position)
	_world.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	print("MELEE ACCEPTANCE ", "OK" if success else "FAIL")
	quit(0 if success else 1)


func _setup() -> void:
	root.size = Vector2i(1280, 720)
	_world = load("res://src/maps/testbed/testbed.tscn").instantiate() as Node3D
	root.add_child(_world)
	for node: Node in _world.find_children("*", "", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	_player = _world.get_node("Player") as CharacterBody3D
	_player.release_mouse()
	_player.position = Vector3(40.0, 0.05, 50.0)
	_player.rotation = Vector3.ZERO
	_player.input_reader.yaw = 0.0
	_player.input_reader.pitch = 0.0
	_player.ads.setup(_player.weapon.data)
	_target = _world.get_node("Targets/TargetDummy_01") as TargetDummy
	_target.position = Vector3(40.0, 0.0, 49.0)
	_target.rotation.y = PI
	_target.move_enabled = false
	_player.update_camera_visuals(0.0)
	_player.camera.current = true
	_player.reset_physics_interpolation()
	_target.reset_physics_interpolation()


func _step(pressed: bool = false) -> void:
	_tick += 1
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = _tick
	inp.melee = pressed
	_player.step_simulation(inp, DELTA)
	_player.update_camera_visuals(DELTA)
	_player.equipment.melee_view.advance(DELTA)


func _swing(label: String) -> void:
	_step(true)
	await _capture(label + "_windup")
	for frame: int in range(1, 49):
		_step()
		if frame == 11:
			await _capture(label + "_strike")
		if frame == 30:
			await _capture(label + "_return")
	print("ACCEPT animation ", label, ": visible=", _player.equipment.melee_view.visible,
		" weapon_visible=", _player.ads_view.visible)


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path: String = "res://.godot/melee_%s.png" % label
	var error: Error = root.get_texture().get_image().save_png(path)
	print("ACCEPT capture=", path, " result=", error)
