extends "res://tests/unit/combat/combat_fixture.gd"


func test_respawn_discards_pending_input_fire_and_lag_history() -> void:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 281
	inp.buttons = PlayerInput.BTN_FIRE
	inp.move = Vector2.ONE.normalized()
	assert_true(actor.server_sim.input_queue.enqueue(inp, 280))
	var combat: NetworkCombat = actor.equipment.combat
	assert_true(combat.history.request(281, FireHistory.shot_seed(281, 42), 42, 280))
	combat.history.slot(281).recorded = true
	players.lag_compensator.record(100)
	_kill()
	Net.tick = 280
	players.respawns.step(280)
	assert_eq(actor.server_sim.input_queue.pending_count, 0)
	assert_null(combat.history.take_ready(280))
	assert_eq(actor.server_sim.input_queue.consume(281).buttons, 0)
	for pose: LagPose in players.lag_compensator.tracks[0].frames:
		assert_eq(pose.tick, -1)


func test_prediction_spawn_floor_rejects_delayed_previous_life_snapshots() -> void:
	var prediction: Prediction = actor.local_controller.prediction
	prediction.configure(preload("res://src/net/default_prediction.tres"))
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 101
	assert_true(prediction.predict(actor, inp, 1.0 / 60.0))
	var state: PredState = PredState.new()
	state.capture(actor)
	assert_true(prediction.receive(state, 101, 100))
	prediction.reset_for_spawn(280)
	assert_false(prediction.receive(state, 101, 279))
	assert_false(prediction.receive(state, 101, 280))
	assert_eq(prediction.reconcile(actor, 1.0 / 60.0), Vector3.ZERO)
	assert_eq(prediction.visual_offset, Vector3.ZERO)
	inp.tick = 300
	assert_true(prediction.predict(actor, inp, 1.0 / 60.0))
	assert_false(prediction.receive(state, 101, 281), "Old acknowledgements cannot refer to reset history")
	state.capture(actor)
	assert_true(prediction.receive(state, 300, 282))
	prediction.reconcile(actor, 1.0 / 60.0)
	assert_eq(prediction.history_misses, 0)


func test_remote_spawn_floor_prevents_interpolation_through_previous_life() -> void:
	var state: PlayerSnapshot = PlayerSnapshot.new()
	state.tick = 279
	actor.remote_view.push_snapshot(state)
	assert_eq(actor.remote_view.interpolator.count, 1)
	var pose: Transform3D = Transform3D(Basis.IDENTITY, Vector3(20, 0, 20))
	actor.remote_view.reset_for_spawn(pose, 280)
	actor.remote_view.push_snapshot(state)
	assert_eq(actor.remote_view.interpolator.count, 0)
	assert_eq(actor.remote_view.global_transform, pose)
	state.tick = 281
	state.position = pose.origin
	actor.remote_view.push_snapshot(state)
	assert_eq(actor.remote_view.interpolator.count, 1)


func test_many_death_spawn_cycles_keep_actor_and_node_counts_constant() -> void:
	var identity: int = actor.get_instance_id()
	var nodes: int = get_tree().get_node_count()
	for cycle: int in range(30):
		Net.tick = 100 + cycle * 400
		_kill()
		Net.tick += 180
		players.respawns.step(Net.tick)
		assert_eq(actor.life.state, PlayerLife.State.ALIVE)
		assert_eq(actor.get_instance_id(), identity)
		assert_eq(players.actors.size(), 1)
		assert_eq(get_tree().get_node_count(), nodes)


func test_dead_owner_input_does_not_alias_or_overwrite_the_life_neutral_buffer() -> void:
	_kill()
	var controller: LocalPlayerController = actor.local_controller
	var original: PlayerInput = controller._input
	controller.history.configure(Net.config.input_history_count)
	var connected_before: bool = Net.is_connected
	Net.is_connected = true
	Input.action_press(InputActions.MOVE_RIGHT)
	for tick: int in [100, 101]:
		Net.tick = tick
		controller._send_input(1.0 / 60.0)
		assert_eq(controller._input, original, "Reader storage stays separate from the life neutral frame")
		assert_eq(controller._input.move, Vector2.ZERO)
		assert_eq(actor.life._neutral.move, Vector2.ZERO)
	Input.action_release(InputActions.MOVE_RIGHT)
	Net.is_connected = connected_before
