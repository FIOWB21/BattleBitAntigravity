extends GutTest

const DELTA: float = 1.0 / 60.0
const EPSILON: float = 0.0001

var _player: Player
var _inp: PlayerInput


func before_each() -> void:
	Settings.reset_to_defaults()
	var bed: Node3D = (load("res://src/maps/testbed/testbed.tscn") as PackedScene).instantiate() as Node3D
	_player = bed.get_node("Player") as Player
	add_child_autofree(bed)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.weapon.setup(_player.weapon.data.duplicate() as WeaponData)
	_player.camera_effects.enabled = false
	_player.release_mouse()
	_inp = PlayerInput.new()
	for tick: int in range(15):
		await get_tree().physics_frame
		_step(0)


func after_each() -> void:
	Settings.reset_to_defaults()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _step(buttons: int, delta: float = DELTA) -> void:
	_inp.tick += 1
	_inp.buttons = buttons
	_player.step_simulation(_inp, delta)
	_player.update_camera_visuals(delta)


func test_camera_model_overlay_and_mouse_share_continuous_ads() -> void:
	assert_not_null(_player.ads_view.model)
	assert_false(_player.ads_view.overlay.visible)
	assert_almost_eq(_player.ads_view.position, _player.weapon.data.viewmodel_hip_offset, EPSILON)
	_step(PlayerInput.BTN_AIM, 0.1)
	assert_almost_eq(_player.camera.fov, 78.75, EPSILON)
	var midpoint: Vector3 = _player.weapon.data.viewmodel_hip_offset.lerp(
		_player.weapon.data.viewmodel_ads_offset, 0.5)
	assert_almost_eq(_player.ads_view.position, midpoint, EPSILON)
	assert_true(_player.ads_view.overlay.visible)
	assert_almost_eq(_player.ads_view.overlay.modulate.a, 0.5, EPSILON)
	var receiver: GeometryInstance3D = _player.ads_view.model.get_node("Receiver") as GeometryInstance3D
	assert_almost_eq(receiver.transparency, 0.5, EPSILON)
	_step(PlayerInput.BTN_AIM, 0.1)
	assert_almost_eq(_player.camera.fov, 67.5, EPSILON)
	assert_almost_eq(_player.ads_view.position, _player.weapon.data.viewmodel_ads_offset, EPSILON)
	assert_almost_eq(receiver.transparency, 1.0, EPSILON)
	assert_almost_eq(_player.input_reader.aim_sensitivity_scale,
		WeaponAds.sensitivity_scale(67.5, 90.0), EPSILON)
	_step(0, 0.2)
	assert_false(_player.ads_view.overlay.visible)
	assert_almost_eq(_player.camera.fov, 90.0, EPSILON)
	assert_almost_eq(_player.input_reader.aim_sensitivity_scale, 1.0, EPSILON)
	assert_almost_eq(receiver.transparency, 0.0, EPSILON)


func test_aim_slows_actual_movement_and_takes_priority_over_sprint() -> void:
	assert_true(_player.is_on_floor())
	_inp.move = Vector2(0.0, 1.0)
	for tick: int in range(60):
		await get_tree().physics_frame
		_step(0)
	var hip_speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	for tick: int in range(60):
		await get_tree().physics_frame
		_step(PlayerInput.BTN_AIM | PlayerInput.BTN_SPRINT)
	var aim_speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	assert_almost_eq(aim_speed, hip_speed * _player.weapon.data.ads_move_speed_mult, EPSILON)
	assert_false(_player.motor.is_sprinting)
	_step(PlayerInput.BTN_SPRINT)
	assert_true(_player.motor.is_sprinting)


func test_fov_setting_during_ads_keeps_zoom_and_sensitivity_in_sync() -> void:
	_step(PlayerInput.BTN_AIM, _player.weapon.data.ads_time)
	Settings.set_fov(120.0)
	assert_almost_eq(_player.camera.fov, 90.0, EPSILON)
	assert_almost_eq(_player.input_reader.aim_sensitivity_scale,
		WeaponAds.sensitivity_scale(90.0, 120.0), EPSILON)
	_step(0, _player.weapon.data.ads_time)
	assert_almost_eq(_player.camera.fov, 120.0, EPSILON)


func test_death_exits_ads_and_weapon_setup_resets_state() -> void:
	_step(PlayerInput.BTN_AIM, 0.2)
	(_player.health_component as HealthComponent).apply_damage(1000.0)
	_step(PlayerInput.BTN_AIM, 0.1)
	assert_eq(_player.ads.target, 0.0)
	assert_almost_eq(_player.camera.fov, 78.75, EPSILON)
	_step(PlayerInput.BTN_AIM, 0.1)
	assert_almost_eq(_player.camera.fov, 90.0, EPSILON)
	_player.weapon.setup(load("res://src/weapons/data/sniper.tres") as WeaponData)
	assert_eq(_player.ads.fraction, 0.0)
	assert_eq(_player.ads.visual_fraction, 0.0)
	assert_eq(_player.input_reader.aim_sensitivity_scale, 1.0)
	assert_eq(_player.ads_view.rig.get_child_count(), 2, "Two cached models after rebuild")


func test_remote_player_has_no_local_model_or_scope() -> void:
	var remote: Player = (load("res://src/player/player.tscn") as PackedScene).instantiate() as Player
	remote.is_local_player = false
	add_child_autofree(remote)
	assert_null(remote.ads_view.model)
	remote.ads_view.apply_ads(1.0)
	assert_false(remote.ads_view.overlay.visible)
	assert_false(remote.ads_view.visible)


func test_partial_ads_blends_authoritative_spread_without_client_damage() -> void:
	var weapon: Weapon = _player.weapon
	weapon.data.spread_hip_deg = 2.0
	weapon.data.spread_ads_deg = 0.0
	weapon.data.recoil_fallback_deg = Vector2.ZERO
	weapon.data.recoil_pattern = []
	weapon.data.recoil_noise_deg = Vector2.ZERO
	var traced: Array[Vector3] = []
	_player.weapon_hitscan.shot_traced.connect(
		func(_tick: int, _pellet: int, direction: Vector3, _hit: HitResult) -> void:
			traced.append(direction))
	_step(PlayerInput.BTN_AIM | PlayerInput.BTN_FIRE, 0.1)
	assert_eq(traced.size(), 1)
	var handling: WeaponHandling = _player.weapon_hitscan.handling
	var expected: Vector3 = handling.spread_direction(Basis.IDENTITY, 1.0,
		_inp.tick, _player.get_multiplayer_authority(), 0)
	assert_almost_eq(traced[0], expected, EPSILON)
	var ammo: int = weapon.ammo_in_mag
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 9), OK)
	api.multiplayer_peer = peer
	var path: NodePath = _player.get_path()
	get_tree().set_multiplayer(api, path)
	_step(PlayerInput.BTN_AIM | PlayerInput.BTN_FIRE, 0.1)
	assert_eq(traced.size(), 1)
	assert_eq(weapon.ammo_in_mag, ammo)
	assert_almost_eq(_player.ads.fraction, 1.0, EPSILON)
	get_tree().set_multiplayer(null, path)
	peer.close()
