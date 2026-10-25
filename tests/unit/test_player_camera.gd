extends GutTest

const PLAYER_SCENE_PATH: String = "res://src/player/player.tscn"


func before_each() -> void:
	Settings.reset_to_defaults()


func after_each() -> void:
	Settings.reset_to_defaults()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_local_input_reader_mouse_deltas_accumulate_yaw_and_clamp_pitch() -> void:
	var reader: LocalInputReader = LocalInputReader.new()
	var sens: float = 0.2

	reader.apply_mouse_delta(Vector2(100.0, -50.0), sens, false)
	assert_almost_eq(
		reader.yaw,
		-deg_to_rad(20.0),
		0.0001,
		"Moving mouse right by 100px at sens 0.2 must change yaw by -20 deg"
	)
	assert_almost_eq(
		reader.pitch,
		deg_to_rad(10.0),
		0.0001,
		"Moving mouse up (-50px) at sens 0.2 must change pitch by +10 deg"
	)

	reader.apply_mouse_delta(Vector2(2000.0, 0.0), sens, false)
	assert_almost_eq(
		reader.yaw,
		-deg_to_rad(420.0),
		0.0001,
		"Yaw must accumulate past 360 deg in LocalInputReader"
	)

	reader.apply_mouse_delta(Vector2(0.0, -1000.0), sens, false)
	assert_almost_eq(
		reader.pitch,
		deg_to_rad(89.0),
		0.0001,
		"Pitch must clamp at +89 deg when looking straight up"
	)

	reader.apply_mouse_delta(Vector2(0.0, 2000.0), sens, false)
	assert_almost_eq(
		reader.pitch,
		-deg_to_rad(89.0),
		0.0001,
		"Pitch must clamp at -89 deg when looking straight down"
	)

	var inp: PlayerInput = reader.read_input()
	assert_almost_eq(inp.yaw, reader.yaw, 0.0001, "PlayerInput.yaw must match reader.yaw")
	assert_almost_eq(inp.pitch, -deg_to_rad(89.0), 0.0001, "PlayerInput.pitch must stay clamped at -89 deg")


func test_local_input_reader_respects_sensitivity_and_invert_y() -> void:
	var reader: LocalInputReader = LocalInputReader.new()
	Settings.set_sensitivity(0.5)
	Settings.set_invert_y(false)

	var motion_up: InputEventMouseMotion = InputEventMouseMotion.new()
	motion_up.relative = Vector2(20.0, -10.0)
	reader.handle_input_event(motion_up)
	assert_almost_eq(reader.yaw, -deg_to_rad(10.0), 0.0001, "Yaw must use Settings sensitivity 0.5")
	assert_almost_eq(reader.pitch, deg_to_rad(5.0), 0.0001, "Non-inverted Y must look up (+pitch) on -relative.y")

	reader.pitch = 0.0
	Settings.set_invert_y(true)
	reader.handle_input_event(motion_up)
	assert_almost_eq(reader.pitch, -deg_to_rad(5.0), 0.0001, "Inverted Y must look down (-pitch) on -relative.y")


func test_camera_fov_from_settings_and_clamping() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var player: Player = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as Player
	tree.root.add_child(player)
	await tree.process_frame

	assert_almost_eq(player.camera.fov, 90.0, 0.001, "Default Camera3D FOV must be 90")

	Settings.set_fov(110.0)
	assert_almost_eq(player.camera.fov, 110.0, 0.001, "Camera3D FOV must update when Settings.set_fov is called")

	Settings.set_fov(40.0)
	assert_almost_eq(Settings.get_fov(), 60.0, 0.001, "Settings FOV must clamp to minimum 60")
	assert_almost_eq(player.camera.fov, 60.0, 0.001, "Camera3D FOV must clamp to minimum 60")

	Settings.set_fov(150.0)
	assert_almost_eq(Settings.get_fov(), 120.0, 0.001, "Settings FOV must clamp to maximum 120")
	assert_almost_eq(player.camera.fov, 120.0, 0.001, "Camera3D FOV must clamp to maximum 120")

	tree.root.remove_child(player)
	player.free()


func test_mouse_capture_and_escape_releases_cursor() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var player: Player = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as Player
	player.is_local_player = true
	tree.root.add_child(player)
	await tree.process_frame

	assert_true(player.is_mouse_captured(), "Local player must capture mouse on _ready")

	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(50.0, -25.0)
	player.handle_input_event(motion)
	assert_almost_eq(player.input_reader.yaw, -deg_to_rad(10.0), 0.0001, "Captured mouse motion must update yaw")
	assert_almost_eq(player.head.rotation.x, deg_to_rad(5.0), 0.0001, "Captured mouse motion must update Head pitch")
	assert_almost_eq(player.rotation.y, 0.0, 0.0001, "Body rotation.y must only change during simulation, not in reader")

	var esc_event: InputEventAction = InputEventAction.new()
	esc_event.action = InputActions.PAUSE_MENU
	esc_event.pressed = true
	player.handle_input_event(esc_event)
	assert_false(player.is_mouse_captured(), "Pressing pause_menu (Esc) must release mouse capture")
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "Input.mouse_mode must be MOUSE_MODE_VISIBLE after Esc")

	var yaw_before: float = player.input_reader.yaw
	player.handle_input_event(motion)
	assert_almost_eq(player.input_reader.yaw, yaw_before, 0.0001, "Mouse motion must be ignored when cursor is released")

	tree.root.remove_child(player)
	player.free()


func test_physics_interpolation_and_camera_effects_toggle() -> void:
	var pi_enabled: bool = bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false))
	assert_true(pi_enabled, "physics/common/physics_interpolation must be enabled in project.godot")

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var player: Player = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as Player
	tree.root.add_child(player)
	await tree.process_frame

	assert_eq(
		player.camera.physics_interpolation_mode,
		Node.PHYSICS_INTERPOLATION_MODE_OFF,
		"Camera3D must use PHYSICS_INTERPOLATION_MODE_OFF to avoid render-frame look conflict"
	)
	assert_not_null(player.camera_effects, "Head must contain CameraEffects node")

	var head_pos_before: Vector3 = player.head.position
	player.velocity = Vector3(0.0, 0.0, -4.0)
	var prev_offset: Vector3 = player.camera_effects.current_offset
	var max_step_jump: float = 0.0
	for _i: int in range(120):
		player.camera_effects.update_effects(1.0 / 60.0, 4.0, true)
		var step_jump: float = (player.camera_effects.current_offset - prev_offset).length()
		max_step_jump = maxf(max_step_jump, step_jump)
		prev_offset = player.camera_effects.current_offset

	assert_gt(
		player.camera_effects.current_offset.length(),
		0.0001,
		"CameraEffects must produce non-zero visual offset when enabled"
	)
	assert_lt(
		max_step_jump,
		0.005,
		"CameraEffects head bob must be continuous across phase wrap without jumps"
	)
	assert_eq(
		player.head.position,
		head_pos_before,
		"CameraEffects must be visual-only and never alter Head position"
	)

	Settings.set_camera_effects_enabled(false)
	assert_false(player.camera_effects.enabled, "CameraEffects must disable via Settings")
	assert_eq(
		player.camera_effects.current_offset,
		Vector3.ZERO,
		"Disabled CameraEffects must reset offset to ZERO"
	)
	assert_eq(
		player.camera_effects.current_rotation,
		Vector3.ZERO,
		"Disabled CameraEffects must reset rotation to ZERO"
	)

	tree.root.remove_child(player)
	player.free()
