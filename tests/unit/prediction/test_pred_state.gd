extends GutTest

var _actor: Player


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_actor = preload("res://src/player/player.tscn").instantiate() as Player
	_actor.is_local_player = false
	_actor.set_physics_process(false)
	add_child(_actor)


func after_each() -> void:
	_actor.free()


func test_wire_roundtrip_restores_mid_transition_motor_and_ads_state() -> void:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 10
	inp.buttons = PlayerInput.BTN_CROUCH | PlayerInput.BTN_AIM
	_actor.movement.step(inp, 1.0 / 60.0)
	_actor.motor.coyote_timer = 0.075
	_actor.motor.stamina = 42.0
	var before: PredState = PredState.new()
	before.capture(_actor)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(PredState.WIRE_BYTES)
	before.encode_into(bytes)
	var received: PredState = PredState.new()
	assert_true(received.decode_from(bytes))
	_actor.stance = PlayerStance.STAND
	_actor.position = Vector3.ONE * 5.0
	_actor.motor.stamina = 1.0
	received.apply_to(_actor, 10)
	var after: PredState = PredState.new()
	after.capture(_actor)
	assert_false(after.differs_from(before, PredictionConfig.new()))
	assert_almost_eq(_actor.motor.coyote_timer, 0.075, 0.00001)
	assert_almost_eq(_actor.collision_shape.position.y,
		_actor.stance_controller.current_capsule_height * 0.5, 0.00001)
	assert_gt(_actor.stance_controller.current_capsule_height, 1.2)
	assert_gt(_actor.ads.fraction, 0.0)
	assert_eq(_actor.motor.stamina, 42.0)


func test_rejects_truncated_nonfinite_and_invalid_stance_owner_state() -> void:
	var state: PredState = PredState.new()
	state.capture(_actor)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(PredState.WIRE_BYTES)
	state.encode_into(bytes)
	assert_false(state.decode_from(bytes.slice(1)))
	bytes.encode_float(0, NAN)
	assert_false(state.decode_from(bytes))
	state.encode_into(bytes)
	bytes.encode_float(PredState.FLAGS * 4, 3.0)
	assert_false(state.decode_from(bytes))


func test_dead_server_state_blocks_client_movement_without_mutating_health() -> void:
	var state: PredState = PredState.new()
	state.capture(_actor)
	state.values[PredState.FLAGS] = PlayerSnapshot.DEAD
	state.apply_to(_actor, 1)
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 2
	inp.move = Vector2.ONE
	inp.buttons = PlayerInput.BTN_JUMP | PlayerInput.BTN_AIM | PlayerInput.BTN_FIRE
	_actor.movement.step(inp, 1.0 / 60.0)
	assert_eq(_actor.velocity.x, 0.0)
	assert_eq(_actor.velocity.z, 0.0)
	assert_eq(_actor.stance, PlayerStance.CROUCH)
	assert_eq(_actor.ads.target, 0.0)
	assert_eq((_actor.health_component as HealthComponent).current, 100.0)
