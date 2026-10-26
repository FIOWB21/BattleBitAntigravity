extends GutTest

const EPSILON: float = 0.00001

var _world: Node3D
var _weapon: Weapon
var _hitscan: WeaponHitscan
var _inp: PlayerInput
var _directions: Array[Vector3] = []


func before_each() -> void:
	_directions.clear()
	_world = Node3D.new()
	_world.position = Vector3(700.0, 50.0, 700.0)
	add_child_autofree(_world)
	_weapon = Weapon.new()
	_weapon.data = WeaponData.new()
	_weapon.data.rpm = 600.0
	_weapon.data.mag_size = 100
	_weapon.data.recoil_pattern = [Vector2(1.0, 0.2), Vector2(1.2, -0.1)]
	_weapon.data.spread_hip_deg = 0.0
	_weapon.data.spread_per_shot_deg = 0.0
	_weapon.data.spread_recovery_deg_per_second = 0.0
	_weapon.ticks_per_second = 60
	_world.add_child(_weapon)
	_hitscan = WeaponHitscan.new()
	_world.add_child(_hitscan)
	_hitscan.setup(_weapon, 7, [])
	_hitscan.shot_traced.connect(_record_trace)
	_inp = PlayerInput.new()


func _record_trace(_tick: int, _pellet: int, direction: Vector3, _hit: HitResult) -> void:
	_directions.append(direction)


func _step(tick: int, buttons: int = PlayerInput.BTN_FIRE,
		stance: int = PlayerStance.STAND, speed: float = 0.0) -> void:
	_inp.tick = tick
	_inp.buttons = buttons
	_hitscan.simulate(_inp, Transform3D(Basis.IDENTITY, _world.global_position), false, stance, speed)


func test_recoil_changes_following_shot_axis_and_can_be_compensated_by_input() -> void:
	_step(0)
	assert_eq(_directions[0], Vector3.FORWARD)
	assert_eq(_hitscan.handling.recoil_deg, Vector2(1.0, 0.2))
	_step(6)
	var expected: Vector3 = -Basis.from_euler(Vector3(deg_to_rad(1.0), deg_to_rad(0.2), 0.0)).z
	assert_almost_eq(_directions[1], expected, EPSILON)
	var compensation: Vector2 = _hitscan.handling.recoil_deg
	_inp.tick = 12
	var basis: Basis = Basis.from_euler(Vector3(-deg_to_rad(compensation.x), -deg_to_rad(compensation.y), 0.0))
	_hitscan.simulate(_inp, Transform3D(basis, _world.global_position))
	assert_almost_eq(_directions[2], Vector3.FORWARD, EPSILON)


func test_dynamic_spread_uses_stance_movement_ads_and_bloom_in_real_rays() -> void:
	_weapon.data.spread_hip_deg = 2.0
	_weapon.data.spread_ads_deg = 0.3
	_weapon.data.spread_per_shot_deg = 0.5
	_weapon.data.pellets = 64
	_step(0, PlayerInput.BTN_FIRE, PlayerStance.STAND, 4.0)
	_assert_cone(0, 64, Vector3.FORWARD, 3.0)
	assert_gt(_directions[0].angle_to(Vector3.FORWARD), 0.0)
	var recoil: Vector2 = _hitscan.handling.recoil_deg
	var axis: Vector3 = -Basis.from_euler(Vector3(deg_to_rad(recoil.x), deg_to_rad(recoil.y), 0.0)).z
	var cone: float = _hitscan.handling.spread_degrees(true, PlayerStance.PRONE, 4.0)
	_step(6, PlayerInput.BTN_FIRE | PlayerInput.BTN_AIM, PlayerStance.PRONE, 4.0)
	_assert_cone(64, 64, axis, cone)
	assert_lt(cone, 3.0)
	var expected: Vector3 = _hitscan.handling.spread_direction(
		Basis.from_euler(Vector3(deg_to_rad(recoil.x), deg_to_rad(recoil.y), 0.0)), cone, 6, 7, 0)
	assert_almost_eq(_directions[64], expected, EPSILON)


func _assert_cone(start: int, count: int, axis: Vector3, angle: float) -> void:
	for index: int in range(start, start + count):
		assert_gte(_directions[index].dot(axis), cos(deg_to_rad(angle)) - EPSILON)


func test_pellets_apply_one_recoil_and_one_bloom_increment() -> void:
	_weapon.data.pellets = 8
	_weapon.data.spread_per_shot_deg = 0.7
	_step(0)
	assert_eq(_directions.size(), 8)
	assert_eq(_weapon.ammo_in_mag, 99)
	assert_eq(_hitscan.handling.recoil_deg, Vector2(1.0, 0.2))
	assert_almost_eq(_hitscan.handling.bloom_deg, 0.7, EPSILON)


func test_blocked_reload_and_duplicate_ticks_add_no_recoil_or_bloom() -> void:
	_weapon.data.spread_per_shot_deg = 0.7
	_step(0)
	var recoil: Vector2 = _hitscan.handling.recoil_deg
	_step(0)
	_inp.tick = 6
	_hitscan.simulate(_inp, Transform3D.IDENTITY, true)
	assert_eq(_hitscan.handling.recoil_deg, recoil)
	assert_almost_eq(_hitscan.handling.bloom_deg, 0.7, EPSILON)
	_step(7, PlayerInput.BTN_RELOAD)
	_step(8)
	assert_eq(_weapon.state, Weapon.State.RELOADING)
	assert_eq(_directions.size(), 1)
	assert_eq(_hitscan.handling.recoil_deg, recoil)
	_step(120, 0)
	assert_eq(_hitscan.handling.recoil_deg, Vector2.ZERO)


func test_weapon_setup_resets_handling_and_replays_identical_rays() -> void:
	_weapon.data.spread_hip_deg = 3.0
	_weapon.data.spread_per_shot_deg = 0.5
	for shot: int in range(8):
		_step(shot * 6)
	var first: Array[Vector3] = _directions.duplicate()
	_weapon.setup(_weapon.data)
	assert_eq(_hitscan.handling.recoil_deg, Vector2.ZERO)
	assert_eq(_hitscan.handling.bloom_deg, 0.0)
	_directions.clear()
	for shot: int in range(8):
		_step(shot * 6)
	assert_eq(_directions, first)
	_hitscan.setup(_weapon, 7, [])
	assert_eq(_hitscan.handling.recoil_deg, Vector2.ZERO)


func test_client_cannot_advance_handling_or_add_impulses() -> void:
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 9), OK)
	api.multiplayer_peer = peer
	var path: NodePath = _world.get_path()
	get_tree().set_multiplayer(api, path)
	_step(0)
	_weapon.fired.emit(0)
	assert_eq(_directions.size(), 0)
	assert_eq(_hitscan.handling.recoil_deg, Vector2.ZERO)
	assert_eq(_hitscan.handling.bloom_deg, 0.0)
	get_tree().set_multiplayer(null, path)
	peer.close()
	_step(0)
	assert_eq(_directions.size(), 1)


func test_player_camera_matches_recoiled_aim_without_modifying_mouse_or_head() -> void:
	var bed: Node3D = (load("res://src/maps/testbed/testbed.tscn") as PackedScene).instantiate() as Node3D
	var player: Player = bed.get_node("Player") as Player
	player.is_local_player = false
	add_child_autofree(bed)
	player.weapon.setup(_weapon.data.duplicate() as WeaponData)
	player.weapon_hitscan.shot_traced.connect(_record_trace)
	player.camera_effects.enabled = false
	var inp: PlayerInput = PlayerInput.new()
	for tick: int in range(15):
		await get_tree().physics_frame
		inp.tick = tick
		player.step_simulation(inp, 1.0 / 60.0)
	assert_true(player.is_on_floor())
	player.input_reader.pitch = 0.2
	player.input_reader.yaw = 0.3
	inp.pitch = 0.2
	inp.yaw = 0.3
	inp.tick = 20
	inp.buttons = PlayerInput.BTN_FIRE
	player.step_simulation(inp, 1.0 / 60.0)
	player.update_camera_visuals(0.0)
	var expected: Basis = Basis.from_euler(Vector3(0.2 + deg_to_rad(1.0), 0.3 + deg_to_rad(0.2), 0.0))
	assert_almost_eq(-player.camera.global_basis.z, -expected.z, EPSILON)
	assert_eq(player.input_reader.pitch, 0.2)
	assert_eq(player.input_reader.yaw, 0.3)
	assert_almost_eq(player.head.rotation.x, 0.2, EPSILON)
	inp.tick = 26
	player.step_simulation(inp, 1.0 / 60.0)
	assert_eq(_directions.size(), 2)
	assert_almost_eq(_directions[1], -expected.z, EPSILON)
	print("ACCEPT 2.4: camera and next shot share recoil axis; mouse/head remain raw")
