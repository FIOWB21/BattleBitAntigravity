extends GutTest

const DT: float = 1.0 / 60.0
var _arena: Node3D
var _server: Player
var _client: Player
var _prediction: Prediction
var _states: Array[PredState] = []
var _wire: PackedByteArray = PackedByteArray()


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_arena = Node3D.new()
	var floor_body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	_arena.add_child(floor_body)
	add_child(_arena)
	_server = _actor()
	_client = _actor()
	_prediction = Prediction.new()
	_prediction.configure(PredictionConfig.new())
	_wire.resize(InputCodec.FRAME_BYTES)
	_states.clear()
	for tick: int in range(201):
		_states.append(PredState.new())
	for tick: int in range(15):
		await get_tree().physics_frame
		_server.movement.step(PlayerInput.new(), DT)
		_client.movement.step(PlayerInput.new(), DT)


func after_each() -> void:
	_arena.free()
	await get_tree().process_frame


func test_ideal_network_delayed_ack_has_zero_reconciliations_for_full_route() -> void:
	for tick: int in range(1, 181):
		await _step(tick)
		if tick > 12 and tick % 2 == 0:
			assert_true(_prediction.receive(_states[tick - 12], tick - 12, tick))
			assert_eq(_prediction.reconcile(_client, DT), Vector3.ZERO)
	assert_eq(_prediction.reconciliations, 0)
	assert_lt(_client.position.distance_to(_server.position), 0.00001)
	assert_eq(_prediction.history_misses, 0)
	assert_eq(_prediction.compared_snapshots, 84)
	assert_almost_eq(_prediction.total_error, 0.0, 0.00001)


func test_first_ack_zero_bootstraps_without_discarding_already_predicted_input() -> void:
	_states[0].capture(_server)
	for tick: int in range(1, 6):
		await _step(tick)
	_prediction.receive(_states[0], 0, 2)
	_prediction.reconcile(_client, DT)
	assert_eq(_prediction.history_misses, 0)
	assert_eq(_prediction.hard_corrections, 0)
	assert_eq(_prediction.replayed_inputs, 5)
	assert_eq(_prediction.compared_snapshots, 0, "Bootstrap without matching history is excluded")
	assert_eq(_prediction.reconciliations, 0)
	assert_lt(_client.position.distance_to(_server.position), 0.00002)
	_prediction.receive(_states[5], 5, 4)
	_prediction.reconcile(_client, DT)
	assert_eq(_prediction.history_misses, 0)
	assert_eq(_prediction.reconciliations, 0)


func test_changed_server_trajectory_replays_unacknowledged_inputs_and_stance() -> void:
	for tick: int in range(1, 76):
		await _step(tick, tick == 43)
	assert_true(_prediction.receive(_states[43], 43, 76))
	var correction: Vector3 = _prediction.reconcile(_client, DT)
	assert_almost_eq(correction.x, -0.5, 0.00002)
	assert_lt(_client.position.distance_to(_server.position), 0.00002)
	assert_lt(_client.velocity.distance_to(_server.velocity), 0.00002)
	assert_almost_eq(_client.stance_controller.current_capsule_height,
		_server.stance_controller.current_capsule_height, 0.00001)
	assert_eq(_prediction.replayed_inputs, 32)
	assert_eq(_prediction.compared_snapshots, 1)
	assert_almost_eq(_prediction.total_error, 0.5, 0.00002)
	assert_eq(_prediction.reconciliations, 1)
	assert_eq(_prediction.hard_corrections, 0)
	assert_almost_eq(_prediction.visual_offset.x, -0.5, 0.00002)
	_prediction.advance_visual(0.05)
	assert_almost_eq(_prediction.visual_offset.x, -0.25, 0.00002)
	_prediction.advance_visual(0.05)
	assert_eq(_prediction.visual_offset, Vector3.ZERO)


func test_velocity_only_disagreement_is_corrected_without_position_threshold() -> void:
	await _step(1)
	_states[1].values[3] += 0.25
	assert_true(_prediction.receive(_states[1], 1, 2))
	_prediction.reconcile(_client, DT)
	assert_almost_eq(_client.velocity.x, _states[1].velocity().x, 0.00001)
	assert_eq(_prediction.reconciliations, 1)


func test_large_error_teleports_without_visual_tail_and_preserves_input_look() -> void:
	await _step(1)
	_states[1].values[0] += 3.0
	_client.input_reader.yaw = 0.75
	_prediction.receive(_states[1], 1, 2)
	_prediction.reconcile(_client, DT)
	assert_almost_eq(_client.position.x, _states[1].position().x, 0.00001)
	assert_eq(_prediction.visual_offset, Vector3.ZERO)
	assert_eq(_prediction.hard_corrections, 1)
	assert_eq(_client.input_reader.yaw, 0.75)


func test_overwritten_history_resets_to_server_instead_of_aliasing_new_tick() -> void:
	var cfg: PredictionConfig = PredictionConfig.new()
	cfg.buffer_capacity = 8
	_prediction.configure(cfg)
	for tick: int in range(1, 31):
		await _step(tick)
	_prediction.receive(_states[1], 1, 32)
	_prediction.reconcile(_client, DT)
	assert_eq(_prediction.history_misses, 1)
	assert_eq(_prediction.hard_corrections, 1)
	assert_eq(_prediction.replayed_inputs, 0)
	assert_eq(_client.position, _states[1].position())
	assert_false(_prediction.receive(_states[2], 2, 31))
	assert_false(_prediction.receive(_states[1], 0, 33))
	assert_false(_prediction.receive(_states[1], 1000, 34))


func test_clock_tick_gaps_use_recorded_order_and_inputs_are_copied() -> void:
	var inp: PlayerInput = _route_input(1)
	_prediction.predict(_client, inp, DT)
	var baseline: PredState = PredState.new()
	baseline.capture(_client)
	baseline.values[0] += 0.5
	for tick: int in [8, 9, 70]:
		inp.tick = tick
		_prediction.predict(_client, inp, DT)
	inp.move = Vector2.LEFT
	_prediction.receive(baseline, 1, 80)
	_prediction.reconcile(_client, DT)
	assert_eq(_prediction.replayed_inputs, 3)
	assert_gt(_client.position.x, 0.5)
	assert_false(_prediction.predict(_client, inp, DT))


func test_airborne_restore_carries_jump_coyote_and_ground_state() -> void:
	for tick: int in range(1, 96):
		await _step(tick, tick == 28)
	_prediction.receive(_states[28], 28, 100)
	_prediction.reconcile(_client, DT)
	assert_lt(_client.position.distance_to(_server.position), 0.00002)
	assert_lt(_client.velocity.distance_to(_server.velocity), 0.00002)
	assert_eq(_client.motor.is_sprinting, _server.motor.is_sprinting)


func test_replay_cannot_fire_consume_ammo_damage_or_spawn_gameplay_nodes() -> void:
	var ammo: int = _client.weapon.ammo_in_mag
	var hp: float = (_client.health_component as HealthComponent).current
	var nodes: int = get_tree().get_node_count()
	for tick: int in range(1, 31):
		await _step(tick, tick == 10, PlayerInput.BTN_FIRE | PlayerInput.BTN_RELOAD)
	_prediction.receive(_states[10], 10, 32)
	_prediction.reconcile(_client, DT)
	assert_eq(_client.weapon.ammo_in_mag, ammo)
	assert_eq((_client.health_component as HealthComponent).current, hp)
	assert_eq(get_tree().get_node_count(), nodes)
	assert_eq(_client.server_sim.simulated_ticks, 0)


func test_repeated_ack_corrects_new_server_repeat_once_and_rejects_old_snapshot() -> void:
	await _step(1)
	_prediction.receive(_states[1], 1, 2)
	_prediction.reconcile(_client, DT)
	_states[1].values[0] += 0.5
	_prediction.receive(_states[1], 1, 4)
	_prediction.reconcile(_client, DT)
	assert_eq(_prediction.reconciliations, 1)
	_prediction.receive(_states[1], 1, 6)
	_prediction.reconcile(_client, DT)
	assert_eq(_prediction.reconciliations, 1)
	assert_false(_prediction.receive(_states[1], 1, 4))


func _actor() -> Player:
	var actor: Player = preload("res://src/player/player.tscn").instantiate() as Player
	actor.is_local_player = false
	actor.position.y = 0.05
	actor.set_physics_process(false)
	_arena.add_child(actor)
	return actor


func _step(tick: int, alter_server: bool = false, extra_buttons: int = 0) -> void:
	await get_tree().physics_frame
	var inp: PlayerInput = _route_input(tick)
	inp.buttons |= extra_buttons
	_server.movement.step(inp, DT)
	if alter_server:
		_server.position.x += 0.5
	_states[tick].capture(_server)
	_prediction.predict(_client, inp, DT)


func _route_input(tick: int) -> PlayerInput:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = tick
	inp.move = Vector2(0.35, 0.8)
	inp.yaw = float(tick) * 0.001
	if tick == 25:
		inp.buttons = PlayerInput.BTN_JUMP
	elif tick >= 40 and tick < 65:
		inp.buttons = PlayerInput.BTN_CROUCH | PlayerInput.BTN_AIM
	elif tick >= 100 and tick < 130:
		inp.buttons = PlayerInput.BTN_PRONE
	else:
		inp.buttons = PlayerInput.BTN_SPRINT
	InputCodec.encode_into(inp, _wire)
	InputCodec.decode_into(_wire, 0, inp)
	return inp
