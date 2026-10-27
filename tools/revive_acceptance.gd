# Приёмка 3.3 на настоящем полигоне: ранение, 180 тиков удержания, смерть и выбор спавна.
extends SceneTree

var _world: Node3D
var _patient: CharacterBody3D
var _medic: CharacterBody3D
var _success: bool = true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_setup()
	await physics_frame
	await physics_frame
	_patient.health_component.apply_damage(1000.0, 7)
	_patient.update_camera_visuals(0.0)
	await _capture("downed")
	var ammo: int = _patient.weapon.ammo_in_mag
	await _revive()
	_success = _success and _patient.health_component.current == 30.0
	_success = _success and _patient.weapon.ammo_in_mag == ammo
	_patient.update_camera_visuals(0.0)
	await _capture("revived")
	_patient.health_component.apply_damage(1000.0, 7)
	_patient.life.step(20.0)
	await _capture("spawn_select")
	_success = _success and _patient.life.view.spawn_panel.visible
	_patient.life.view.spawn_button.pressed.emit()
	_success = _success and _patient.health_component.current == 100.0
	_success = _success and not _patient.life.view.spawn_panel.visible
	print("REVIVE ACCEPTANCE ", "OK" if _success else "FAIL",
		" | hold=180 ticks | revived=30 HP | spawn=100 HP | ammo unchanged=",
		_patient.weapon.ammo_in_mag == ammo)
	_world.queue_free()
	await process_frame
	await process_frame
	quit(0 if _success else 1)


func _setup() -> void:
	_world = load("res://src/maps/testbed/testbed.tscn").instantiate() as Node3D
	root.add_child(_world)
	_patient = _world.get_node("Player") as CharacterBody3D
	_medic = load("res://src/player/player.tscn").instantiate() as CharacterBody3D
	_medic.set("is_local_player", false)
	_medic.position = _patient.position + Vector3(0, 0, 1.5)
	_medic.set("class_data", load("res://src/classes/data/medic.tres"))
	_world.add_child(_medic)
	_freeze(_world)
	_patient.release_mouse()


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_freeze(child)


func _revive() -> void:
	await physics_frame
	await physics_frame
	var inp: PlayerInput = PlayerInput.new()
	inp.buttons = PlayerInput.BTN_INTERACT
	var offset: Vector3 = _patient.head.global_position - _medic.head.global_position
	inp.pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
	inp.yaw = atan2(-offset.x, -offset.z)
	for tick: int in range(181):
		inp.tick = tick
		_medic.life.interaction.simulate(inp, 1.0 / Engine.physics_ticks_per_second)
		if tick == 179:
			_success = _success and _patient.health_component.current == 0.0
	print("ACCEPT revive: health=", _patient.health_component.current,
		" stance=", _patient.stance, " progress=", _medic.life.interaction.progress)


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("ACCEPT state: ", label, " health=", _patient.health_component.current)
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/revive_" + label + ".png")
