# Приёмка 2.10 на существующем полигоне; снимки сохраняются только в .godot.
extends SceneTree

var _world: Node3D
var _system: ProjectileSystem
var _effects: ProjectileEffects
var _camera: Camera3D
var _markers: Array[MeshInstance3D] = []
var _bounces: int = 0
var _detonations: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 120
	_setup()
	await physics_frame
	await physics_frame
	var data: ProjectileData = load("res://src/weapons/projectiles/frag.tres").duplicate() as ProjectileData
	data.drag = 0.0
	var grenade: Projectile = _system.launch(data, Vector3(-20.0, 1.5, -11.0), Vector3(0.0, 2.0, -8.0))
	grenade.bounced.connect(func(_point: Vector3, _normal: Vector3) -> void: _bounces += 1)
	var nodes: int = get_node_count()
	for tick: int in range(180):
		grenade.simulate(1.0 / 60.0)
		_effects.advance(1.0 / 60.0)
		if tick % 3 == 0:
			_markers[tick / 3].global_position = grenade.global_position
			_markers[tick / 3].visible = true
		if tick == 29:
			await _capture("trajectory")
		if get_node_count() != nodes:
			printerr("ACCEPT FAIL: node count changed at tick=", tick)
			quit(1)
			return
	print("ACCEPT 2.10: ticks=180 bounces=", _bounces, " detonations=", _detonations,
		" fuse=", grenade.age, " point=", grenade.global_position, " nodes=", nodes)
	_effects.advance(0.12)
	await _capture("frag")
	var variants_ok: bool = await _show_smoke_flash_rocket()
	var success: bool = variants_ok and _bounces > 0 and not grenade.active and grenade.age == 3.0
	await _finish(success)


func _finish(success: bool) -> void:
	_world.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	print("PROJECTILE ACCEPTANCE ", "OK" if success else "FAIL")
	quit(0 if success else 1)


func _setup() -> void:
	root.size = Vector2i(1280, 720)
	_world = load("res://src/maps/testbed/testbed.tscn").instantiate() as Node3D
	root.add_child(_world)
	for node: Node in _world.find_children("*", "", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	_world.get_node("Player").call("release_mouse")
	_camera = Camera3D.new()
	_world.add_child(_camera)
	_camera.position = Vector3(-14.0, 4.0, -8.0)
	_camera.look_at(Vector3(-20.0, 1.0, -13.0))
	_camera.current = true
	_system = ProjectileSystem.new()
	_system.capacity = 4
	_world.add_child(_system)
	_system.set_physics_process(false)
	_system.exploded.connect(func(_data: ProjectileData, _point: Vector3, _attacker: int) -> void:
		_detonations += 1)
	_effects = ProjectileEffects.new()
	_world.add_child(_effects)
	_effects.setup(_system, _camera)
	_effects.set_process(false)
	_setup_markers()


func _setup_markers() -> void:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.07
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.1, 1.0, 0.3)
	sphere.material = material
	for index: int in range(60):
		var marker: MeshInstance3D = MeshInstance3D.new()
		marker.mesh = sphere
		marker.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		marker.visible = false
		_world.add_child(marker)
		_markers.append(marker)


func _show_smoke_flash_rocket() -> bool:
	_effects.advance(10.0)
	var point: Vector3 = Vector3(-20.0, 0.2, -12.0)
	_effects.present(load("res://src/weapons/projectiles/smoke.tres") as ProjectileData, point)
	_effects.advance(2.0)
	await _capture("smoke")
	_effects.advance(20.0)
	_effects.present(load("res://src/weapons/projectiles/flash.tres") as ProjectileData,
		_camera.global_position - _camera.global_basis.z * 2.0)
	_effects.advance(0.3)
	print("ACCEPT cosmetic flash: alpha=", _effects.flash.color.a,
		" ringing=", _effects.ringing.playing, " duration=", _effects.sensory_remaining)
	var flash_ok: bool = _effects.flash.color.a > 0.0 and _effects.ringing.playing
	await _capture("flash")
	_effects.advance(20.0)
	var rocket: Projectile = _system.launch(load("res://src/weapons/projectiles/rocket.tres") as ProjectileData,
		Vector3(-20.0, 1.5, -11.0), Vector3(0.0, 0.0, -80.0))
	for tick: int in range(3):
		rocket.simulate(1.0 / 60.0)
		_effects.advance(1.0 / 60.0)
	await _capture("rocket")
	print("ACCEPT rocket impact: active=", rocket.active, " point=", rocket.global_position)
	_effects.advance(20.0)
	return flash_ok and not rocket.active


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path: String = "res://.godot/projectile_%s.png" % label
	var error: Error = root.get_texture().get_image().save_png(path)
	print("ACCEPT capture=", path, " result=", error)
