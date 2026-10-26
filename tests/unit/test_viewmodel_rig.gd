extends GutTest

var _player: Player


func before_each() -> void:
	_player = (load("res://src/player/player.tscn") as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.release_mouse()


func test_rig_is_under_camera_and_all_cached_models_use_private_overlay_materials() -> void:
	var rig: ViewmodelRig = _player.ads_view.rig
	assert_true(_player.camera.is_ancestor_of(rig))
	assert_eq(rig.get_child_count(), 2)
	var materials: Array[Material] = []
	for model: Node in rig.get_children():
		for child: Node in model.get_children():
			var mesh: MeshInstance3D = child as MeshInstance3D
			var material: BaseMaterial3D = mesh.get_active_material(0) as BaseMaterial3D
			assert_true(material.use_fov_override)
			assert_true(material.no_depth_test)
			assert_eq(material.fov_override, rig.config.fov)
			assert_eq(material.render_priority, ViewmodelRig.RENDER_PRIORITY)
			assert_null(mesh.get_surface_override_material(0))
			assert_false(materials.has(material))
			materials.append(material)
			assert_true(mesh.ignore_occlusion_culling)
			assert_eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_world_fov_changes_do_not_change_viewmodel_projection() -> void:
	var mesh: MeshInstance3D = _player.ads_view.model.get_node("Receiver") as MeshInstance3D
	var material: BaseMaterial3D = mesh.get_active_material(0) as BaseMaterial3D
	for fov: float in [60.0, 90.0, 120.0]:
		_player.camera.fov = fov
		_player.ads_view.rig.advance(0.1, 0.0, true, false)
		assert_eq(material.fov_override, 75.0)


func test_scene_materials_remain_unchanged_and_repeated_immediate_free_is_safe() -> void:
	var scene: PackedScene = load("res://src/weapons/temporary_viewmodel.tscn") as PackedScene
	var model: Node = scene.instantiate()
	var mesh: MeshInstance3D = model.get_node("Receiver") as MeshInstance3D
	var source_mesh: Mesh = mesh.mesh
	var material: BaseMaterial3D = mesh.get_active_material(0) as BaseMaterial3D
	assert_false(material.use_fov_override)
	assert_false(material.no_depth_test)
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED)
	model.free()
	for cycle: int in range(3):
		var player: Player = (load("res://src/player/player.tscn") as PackedScene).instantiate() as Player
		add_child(player)
		assert_ne((player.ads_view.model.get_node("Receiver") as MeshInstance3D).mesh, source_mesh)
		player.free()
		await get_tree().process_frame


func test_authoritative_fire_kicks_and_blocked_or_reloading_weapon_does_not() -> void:
	var rig: ViewmodelRig = _player.ads_view.rig
	var weapon: Weapon = _player.weapon
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.buttons = PlayerInput.BTN_FIRE
	weapon.simulate(inp, true)
	assert_eq(rig.motion.offset.velocity, Vector3.ZERO)
	inp.tick += 1
	inp.buttons = 0
	weapon.simulate(inp)
	inp.tick += 1
	inp.buttons = PlayerInput.BTN_FIRE
	weapon.simulate(inp)
	assert_eq(rig.motion.offset.velocity, rig.config.kick_velocity)
	rig.motion.reset()
	inp.tick += 1
	inp.buttons = PlayerInput.BTN_RELOAD
	weapon.simulate(inp)
	assert_true(rig.motion.reloading)
	inp.tick += 1
	inp.buttons = PlayerInput.BTN_FIRE
	weapon.simulate(inp)
	assert_eq(rig.motion.offset.velocity, Vector3.ZERO)


func test_shot_signal_kicks_once_and_binding_disconnects_previous_weapon() -> void:
	var rig: ViewmodelRig = _player.ads_view.rig
	var primary: Weapon = _player.weapon
	var secondary: Weapon = _player.inventory.weapon_at(2)
	var ammo: int = primary.ammo_in_mag
	primary.fired.emit(1)
	assert_eq(rig.motion.offset.velocity, rig.config.kick_velocity)
	assert_eq(primary.ammo_in_mag, ammo, "Presentation cannot spend ammunition")
	rig.bind_weapon(secondary)
	primary.fired.emit(2)
	assert_eq(rig.motion.offset.velocity, Vector3.ZERO)
	secondary.fired.emit(3)
	assert_eq(rig.motion.offset.velocity, rig.config.kick_velocity)
	rig.bind_weapon(secondary)
	secondary.fired.emit(4)
	assert_eq(rig.motion.offset.velocity, rig.config.kick_velocity)
	rig.bind_weapon(null)
	secondary.fired.emit(5)
	assert_eq(rig.motion.offset.velocity, Vector3.ZERO)


func test_reload_signals_use_tactical_and_empty_duration_and_handle_cancellation() -> void:
	var weapon: Weapon = _player.weapon
	var rig: ViewmodelRig = _player.ads_view.rig
	weapon.reload_started.emit()
	assert_eq(rig.motion.reload_duration, weapon.data.reload_time)
	rig.advance(0.5, 0.0, true, false)
	assert_true(rig.motion.reloading)
	weapon.reload_cancelled.emit()
	assert_false(rig.motion.reloading)
	weapon.ammo_in_mag = 0
	weapon.reload_started.emit()
	assert_eq(rig.motion.reload_duration, weapon.data.reload_empty_time)
	weapon.reload_finished.emit()
	assert_false(rig.motion.reloading)


func test_actual_mouse_event_produces_sway_without_changing_weapon_state() -> void:
	_player.capture_mouse()
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.relative = Vector2(25.0, -10.0)
	event.screen_relative = event.relative
	_player.handle_input_event(event)
	_player.update_camera_visuals(1.0 / 60.0)
	assert_gt(_player.ads_view.rig.rotation.length(), 0.0)
	assert_eq(_player.weapon.state, Weapon.State.IDLE)
	_player.release_mouse()


func test_remote_player_allocates_no_viewmodel_rig() -> void:
	var remote: Player = (load("res://src/player/player.tscn") as PackedScene).instantiate() as Player
	remote.is_local_player = false
	add_child_autofree(remote)
	assert_null(remote.ads_view.rig)
	assert_null(remote.ads_view.model)


func test_custom_resource_changes_fov_and_reconfigure_resets_pose() -> void:
	var data: WeaponData = _player.weapon.data.duplicate() as WeaponData
	data.viewmodel_config = ViewmodelRig.DEFAULT_CONFIG.duplicate() as ViewmodelConfig
	data.viewmodel_config.fov = 85.0
	_player.weapon.setup(data)
	var mesh: MeshInstance3D = _player.ads_view.model.get_node("Receiver") as MeshInstance3D
	assert_eq((mesh.get_active_material(0) as BaseMaterial3D).fov_override, 85.0)
	_player.weapon.fired.emit(1)
	_player.ads_view.rig.advance(0.01, 0.0, true, false)
	assert_gt(_player.ads_view.rig.position.length(), 0.0)
	_player.weapon.setup(data)
	assert_eq(_player.ads_view.rig.position, Vector3.ZERO)
	assert_eq(_player.ads_view.rig.motion.offset.velocity, Vector3.ZERO)
