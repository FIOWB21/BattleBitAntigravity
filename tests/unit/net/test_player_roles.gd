extends GutTest

var _actor: Player
var _branch: Node3D
var _api: SceneMultiplayer


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func after_each() -> void:
	if is_instance_valid(_actor):
		_actor.free()
	if Net.is_connected:
		Net.disconnect_all()
	if _api != null:
		_api.multiplayer_peer.close()
		get_tree().set_multiplayer(null, _branch.get_path())
		_api = null
	if is_instance_valid(_branch):
		_branch.free()
	Game.detect_runtime_flags(PackedStringArray(), false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().process_frame


func test_offline_player_keeps_local_controls_and_server_simulation() -> void:
	_actor = preload("res://src/player/player.tscn").instantiate() as Player
	add_child(_actor)
	_actor.set_physics_process(false)
	assert_true(_actor.local_controller.enabled)
	assert_true(_actor.server_sim.enabled)
	assert_true(_actor.camera.current)
	assert_null(_actor.local_controller.hud, "Offline map owns its existing HUD")
	assert_false(_actor.remote_view.visible)


func test_server_remote_has_input_authority_without_camera_hud_or_local_simulation() -> void:
	_actor = preload("res://src/player/player.tscn").instantiate() as Player
	_actor.network_owner_id = 42
	_actor.get_node("LocalPlayerController").set_multiplayer_authority(42)
	add_child(_actor)
	assert_eq(_actor.get_multiplayer_authority(), 1)
	assert_eq(_actor.local_controller.get_multiplayer_authority(), 42)
	assert_false(_actor.local_controller.enabled)
	assert_false(_actor.camera.current)
	assert_null(_actor.local_controller.hud)
	assert_true(_actor.remote_view.visible)
	assert_true(_actor.server_sim.enabled)
	var before: Vector3 = _actor.position
	_actor._physics_process(1.0)
	assert_eq(_actor.position, before, "Remote never reads this machine's input")
	assert_almost_eq((_actor.remote_view.capsule.mesh as CapsuleMesh).height, 1.8, 0.001)


func test_dedicated_player_has_no_local_presentation_even_for_peer_one() -> void:
	Game.is_dedicated = true
	_actor = preload("res://src/player/player.tscn").instantiate() as Player
	_actor.network_owner_id = 1
	add_child(_actor)
	assert_false(_actor.is_local_player)
	assert_false(_actor.camera.current)
	assert_false(_actor.local_controller.enabled)
	assert_null(_actor.local_controller.hud)
	assert_true(_actor.remote_view.visible)
	assert_true(_actor.server_sim.enabled)


func test_client_cannot_execute_server_simulation_or_change_gameplay_state() -> void:
	_branch = Node3D.new()
	add_child(_branch)
	_api = SceneMultiplayer.new()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 1), OK)
	_api.multiplayer_peer = peer
	get_tree().set_multiplayer(_api, _branch.get_path())
	_actor = preload("res://src/player/player.tscn").instantiate() as Player
	_actor.network_owner_id = 42
	_branch.add_child(_actor)
	assert_false(_actor.server_sim.enabled)
	assert_eq(_actor.server_sim.process_mode, Node.PROCESS_MODE_DISABLED)
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.move = Vector2.ONE
	inp.yaw = 1.0
	inp.buttons = PlayerInput.BTN_FIRE
	var before: Transform3D = _actor.transform
	var ammo: int = _actor.weapon.ammo_in_mag
	_actor.server_sim.simulate(inp, 1.0)
	_actor.step_simulation(inp, 1.0)
	(_actor.health_component as HealthComponent).apply_damage(100.0)
	assert_eq(_actor.transform, before)
	assert_eq(_actor.weapon.ammo_in_mag, ammo)
	assert_eq((_actor.health_component as HealthComponent).current, 100.0)


func test_listen_owner_uses_wire_queue_and_simulates_once_per_server_tick() -> void:
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(socket.bind(0, "127.0.0.1"), OK)
	var port: int = socket.get_local_port()
	socket.close()
	Net.local_nickname = "InputHost"
	assert_eq(Net.start_server(port, 2, true), OK)
	_actor = preload("res://src/player/player.tscn").instantiate() as Player
	_actor.network_owner_id = 1
	_actor.set_physics_process(false)
	add_child(_actor)
	Net.tick = 100
	Input.action_press(InputActions.MOVE_RIGHT)
	_actor.local_controller.physics_step(1.0 / 60.0)
	Input.action_release(InputActions.MOVE_RIGHT)
	assert_eq(_actor.server_sim.input_queue.pending_count, 1)
	assert_eq(_actor.server_sim.simulated_ticks, 0, "Collection does not execute gameplay")
	_actor.server_sim.physics_step(1.0 / 60.0)
	assert_eq(_actor.server_sim.simulated_ticks, 1)
	assert_eq(_actor.server_sim.input_queue.last_input_tick, 100)
	assert_gt(_actor.velocity.x, 0.0)
	_actor.server_sim.physics_step(1.0 / 60.0)
	assert_eq(_actor.server_sim.simulated_ticks, 1)


func test_direct_rpc_call_without_remote_owner_is_ignored() -> void:
	_actor = preload("res://src/player/player.tscn").instantiate() as Player
	_actor.network_owner_id = 42
	add_child(_actor)
	var history: InputHistory = InputHistory.new()
	history.configure(Net.config.input_history_count)
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	history.push(inp)
	_actor.server_sim.submit_input(history.packet)
	_actor.server_sim.receive_local(history.packet)
	assert_eq(_actor.server_sim.input_queue.pending_count, 0)
