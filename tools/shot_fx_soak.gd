# Приёмка 2.9: 30 реальных секунд стрельбы, счётчик узлов и снимки Forward+.
extends SceneTree

const DURATION_TICKS: int = 1800
const DURATION_MSEC: int = 30000
const PLATE_DISTANCE: float = 12.0
const PLATE_SPACING: float = 2.2
const CAPTURE_TICKS: Array[int] = [360, 364, 368, 372, 376, 380]

var _world: Node3D
var _weapon: Weapon
var _hitscan: WeaponHitscan
var _effects: ShotEffects
var _camera: Camera3D
var _view: WeaponAdsView
var _input: PlayerInput = PlayerInput.new()
var _surface_hits: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_setup_world()
	_setup_weapon()
	await physics_frame
	await physics_frame
	var expected: int = get_node_count()
	var start: int = Time.get_ticks_msec()
	var tick: int = 0
	while tick < DURATION_TICKS or Time.get_ticks_msec() - start < DURATION_MSEC:
		await physics_frame
		_input.tick = tick
		var target: Vector3 = _plate_position(_effects.shots_presented % 6)
		var aim: Basis = Basis.looking_at(_camera.global_position.direction_to(target))
		_hitscan.simulate(_input, Transform3D(aim, _camera.global_position))
		if get_node_count() != expected:
			printerr("SOAK FAIL nodes: ", expected, " -> ", get_node_count(), " tick=", tick)
			quit(1)
			return
		if tick % 600 == 0:
			print("SOAK tick=", tick, " nodes=", expected, " shots=", _effects.shots_presented)
		if tick in CAPTURE_TICKS and DisplayServer.get_name() != "headless":
			await _capture(tick)
		tick += 1
	var elapsed: float = (Time.get_ticks_msec() - start) / 1000.0
	print("SOAK OK seconds=", elapsed, " nodes=", expected, " shots=", _effects.shots_presented,
		" decals=", _effects.decals.pool.acquired_count, " surface_hits=", _surface_hits)
	var success: bool = _effects_shots_valid()
	_world.queue_free()
	await process_frame
	await process_frame
	quit(0 if success else 1)


func _effects_shots_valid() -> bool:
	for hits: int in _surface_hits:
		if hits < 75:
			return false
	return true


func _plate_position(index: int) -> Vector3:
	return Vector3((index - 2.5) * PLATE_SPACING, 1.65, -PLATE_DISTANCE)


func _setup_world() -> void:
	root.size = Vector2i(1280, 720)
	_world = Node3D.new()
	root.add_child(_world)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.65, 2.0)
	_camera.fov = 75.0
	_world.add_child(_camera)
	_camera.current = true
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.06, 0.08, 0.1)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	_world.add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -25.0, 0.0)
	_world.add_child(sun)
	for index: int in range(6):
		_add_plate(index)


func _add_plate(index: int) -> void:
	var plate: StaticBody3D = StaticBody3D.new()
	plate.position = _plate_position(index)
	plate.set_meta(&"surface_type", ShotSurface.NAMES[index])
	_world.add_child(plate)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(2.0, 2.5, 0.2)
	collision.shape = shape
	plate.add_child(collision)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = shape.size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.42, 0.44)
	box.material = material
	mesh.mesh = box
	plate.add_child(mesh)
	var label: Label3D = Label3D.new()
	label.text = String(ShotSurface.NAMES[index])
	label.position = Vector3(0.0, 1.6, 0.0)
	label.font_size = 48
	plate.add_child(label)


func _setup_weapon() -> void:
	_weapon = Weapon.new()
	_weapon.data = WeaponData.new()
	_weapon.data.rpm = 900.0
	_weapon.data.mag_size = 10000
	_weapon.data.spread_hip_deg = 0.0
	_weapon.data.spread_per_shot_deg = 0.0
	_weapon.data.recoil_fallback_deg = Vector2.ZERO
	_weapon.data.recoil_noise_deg = Vector2.ZERO
	_world.add_child(_weapon)
	_view = WeaponAdsView.new()
	_camera.add_child(_view)
	_view.setup(_weapon, true)
	_hitscan = WeaponHitscan.new()
	_world.add_child(_hitscan)
	_hitscan.setup(_weapon, 1, [])
	_hitscan.shot_traced.connect(_on_traced)
	_effects = ShotEffects.new()
	_world.add_child(_effects)
	_effects.setup(_camera, true, _view)
	_effects.bind_weapon(_weapon, _hitscan)
	_input.buttons = PlayerInput.BTN_FIRE


func _on_traced(_tick: int, _pellet: int, _direction: Vector3, hit: HitResult) -> void:
	if hit.hit:
		_surface_hits[ShotSurface.resolve(hit)] += 1


func _capture(tick: int) -> void:
	var feedback: DamageEvent = DamageEvent.new()
	feedback.damage = 1.0
	feedback.zone = HitboxZone.HEAD if tick % 12 == 0 else HitboxZone.TORSO
	_effects.present_damage(feedback)
	await RenderingServer.frame_post_draw
	var path: String = "res://.godot/shot_fx_%d.png" % tick
	var error: Error = root.get_texture().get_image().save_png(path)
	print("SOAK capture=", path, " result=", error)
