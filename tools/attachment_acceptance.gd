# Приёмка 2.13: настоящие серверные лучи, команда лодаута, модели и снимки.
extends SceneTree

const SHOTS: int = 24
const PLOT_SCALE: float = 5000.0


class SpreadPlot extends Control:
	var before: PackedVector2Array = []
	var after: PackedVector2Array = []
	var caption: String = ""


	func _draw() -> void:
		draw_style_box(_panel(), Rect2(24, 30, 760, 400))
		draw_string(ThemeDB.fallback_font, Vector2(44, 60), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
		for column: int in range(2):
			var center: Vector2 = Vector2(210 + column * 380, 250)
			draw_arc(center, 140.0, 0.0, TAU, 96, Color(0.4, 0.5, 0.6), 1.0, true)
			draw_line(center - Vector2(150, 0), center + Vector2(150, 0), Color(0.3, 0.4, 0.5))
			draw_line(center - Vector2(0, 150), center + Vector2(0, 150), Color(0.3, 0.4, 0.5))
			var points: PackedVector2Array = before if column == 0 else after
			for point: Vector2 in points:
				draw_circle(center + point, 3.5, Color(1.0, 0.5, 0.15) if column == 0 else Color(0.3, 1.0, 0.6))
			draw_string(ThemeDB.fallback_font, center + Vector2(-100, 172),
				"BASE / same seed" if column == 0 else "ATTACHED / same scale", HORIZONTAL_ALIGNMENT_LEFT, -1, 17)


	func _panel() -> StyleBoxFlat:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.025, 0.045, 0.065, 0.94)
		return style


var _world: Node3D
var _player: CharacterBody3D
var _console: RefCounted
var _profile: WeaponData
var _directions: Array[Vector3] = []
var _before: Array[Vector3] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 120
	_setup()
	await physics_frame
	await physics_frame
	var base_spread: float = _player.weapon.data.spread_hip_deg
	_before = _sample()
	await _capture("base")
	_player.weapon.setup(_profile)
	var ammo: int = _player.weapon.ammo_in_mag
	for name: String in ["sight", "muzzle", "barrel", "grip", "magazine"]:
		print("ACCEPT command: ", _console.call("execute_command", "attachment equip " + name))
	var equipped_without_refill: bool = _player.weapon.ammo_in_mag == ammo
	var attached_spread: float = _player.weapon.data.spread_hip_deg
	var attached: Array[Vector3] = _sample()
	var success: bool = _validate(attached, equipped_without_refill)
	_add_plot(base_spread, attached_spread, attached)
	await _capture("attached")
	_player.ads_view.position = Vector3(0.2, -0.12, -0.8)
	await _capture("models")
	print("ACCEPT 2.13: hip=", base_spread, " -> ", attached_spread,
		" rays=", _before.size(), "/", attached.size(), " no_refill=", equipped_without_refill)
	success = _check_repeated_equip() and success
	_world.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	print("ATTACHMENT ACCEPTANCE ", "OK" if success else "FAIL")
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
	_profile = _player.weapon.data.duplicate() as WeaponData
	_profile.recoil_pattern = []
	_profile.recoil_fallback_deg = Vector2.ZERO
	_profile.recoil_noise_deg = Vector2.ZERO
	_profile.spread_per_shot_deg = 0.0
	_player.weapon.setup(_profile)
	_player.update_camera_visuals(0.0)
	_player.camera.current = true
	_player.reset_physics_interpolation()
	_console = (load("res://src/ui/debug_console.gd") as GDScript).new()
	_player.weapon_hitscan.shot_traced.connect(_on_traced)


func _sample() -> Array[Vector3]:
	_directions.clear()
	var inp: PlayerInput = PlayerInput.new()
	var interval: int = maxi(2, ceili(_player.weapon.data.cooldown() * Engine.physics_ticks_per_second))
	var aim: Transform3D = Transform3D(Basis.IDENTITY, _player.head.global_position)
	for shot: int in range(SHOTS):
		inp.tick = 1 + shot * interval
		inp.buttons = PlayerInput.BTN_FIRE
		_player.weapon_hitscan.simulate(inp, aim)
		inp.tick += 1
		inp.buttons = 0
		_player.weapon_hitscan.simulate(inp, aim)
	inp.tick += interval
	_player.weapon_hitscan.simulate(inp, aim)
	return _directions.duplicate()


func _on_traced(_tick: int, _pellet: int, direction: Vector3, _hit: HitResult) -> void:
	_directions.append(direction)


func _validate(attached: Array[Vector3], no_refill: bool) -> bool:
	if attached.size() != SHOTS or _before.size() != SHOTS or not no_refill:
		return false
	for index: int in range(SHOTS):
		if Vector3.FORWARD.angle_to(attached[index]) >= Vector3.FORWARD.angle_to(_before[index]):
			return false
	return _player.weapon.ammo_in_mag == _profile.mag_size - SHOTS


func _check_repeated_equip() -> bool:
	var nodes: int = get_node_count()
	for repeat: int in range(100):
		_console.call("execute_command", "attachment equip grip")
		if get_node_count() != nodes:
			return false
	print("ACCEPT 2.13: 100 replacements, nodes=", nodes, " -> ", get_node_count())
	return true


func _add_plot(base: float, attached: float, directions: Array[Vector3]) -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	_world.add_child(canvas)
	canvas.layer = 20
	var plot: SpreadPlot = SpreadPlot.new()
	canvas.add_child(plot)
	plot.caption = "24 authoritative rays | hip %.3f -> %.3f degrees" % [base, attached]
	for direction: Vector3 in _before:
		plot.before.append(Vector2(direction.x, -direction.y) * PLOT_SCALE)
	for direction: Vector3 in directions:
		plot.after.append(Vector2(direction.x, -direction.y) * PLOT_SCALE)


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	_player.equipment.effects.advance(1.0)
	await RenderingServer.frame_post_draw
	var path: String = "res://.godot/attachment_%s.png" % label
	print("ACCEPT capture=", path, " result=", root.get_texture().get_image().save_png(path))
