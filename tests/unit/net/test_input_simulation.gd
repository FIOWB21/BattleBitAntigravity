extends GutTest

const DT: float = 1.0 / 60.0
const SEPARATION: Vector3 = Vector3(0.0, 0.0, 20.0)
var _arena: Node3D
var _server: CharacterBody3D
var _local: CharacterBody3D
var _server_motor: PlayerMotor
var _local_motor: PlayerMotor
var _config: MovementConfig = preload("res://src/player/default_movement.tres")


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_arena = Node3D.new()
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	floor_shape.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(floor_shape)
	_arena.add_child(floor_body)
	_server = _body(Vector3(0.0, 0.05, 0.0))
	_local = _body(_server.position + SEPARATION)
	_server_motor = PlayerMotor.new()
	_local_motor = PlayerMotor.new()
	add_child(_arena)
	await get_tree().physics_frame
	for tick: int in range(15):
		await get_tree().physics_frame
		_server_motor.simulate(_server, PlayerInput.new(), _config, PlayerStance.STAND, DT)
		_local_motor.simulate(_local, PlayerInput.new(), _config, PlayerStance.STAND, DT)


func after_each() -> void:
	_arena.free()
	await get_tree().process_frame


func test_server_queue_and_local_motor_match_each_tick_for_same_wire_inputs() -> void:
	var cfg: NetworkConfig = NetworkConfig.new()
	var queue: ServerInputQueue = ServerInputQueue.new()
	queue.configure(cfg, 60)
	var history: InputHistory = InputHistory.new()
	history.configure(cfg.input_history_count)
	var local_input: PlayerInput = PlayerInput.new()
	for tick: int in range(1, 181):
		var original: PlayerInput = _sequence(tick)
		assert_true(history.push(original))
		assert_eq(queue.receive(history.packet, tick), 1)
		assert_eq(queue.receive(history.packet, tick), 0)
		assert_true(InputCodec.decode_into(history.packet, ((tick - 1) % 6) * 12, local_input))
		var server_input: PlayerInput = queue.consume(tick)
		await get_tree().physics_frame
		_server_motor.simulate(_server, server_input, _config, PlayerStance.STAND, DT)
		_local_motor.simulate(_local, local_input, _config, PlayerStance.STAND, DT)
		assert_lt((_server.position - (_local.position - SEPARATION)).length(), 0.00001)
		assert_lt((_server.velocity - _local.velocity).length(), 0.00001)
	assert_gt(Vector2(_server.position.x, _server.position.z).length(), 1.0)


func test_quantized_server_motion_stays_within_derived_analog_error_bound() -> void:
	var cfg: NetworkConfig = NetworkConfig.new()
	var queue: ServerInputQueue = ServerInputQueue.new()
	queue.configure(cfg, 60)
	var history: InputHistory = InputHistory.new()
	history.configure(cfg.input_history_count)
	for tick: int in range(1, 121):
		var original: PlayerInput = _sequence(tick)
		history.push(original)
		queue.receive(history.packet, tick)
		await get_tree().physics_frame
		_server_motor.simulate(_server, queue.consume(tick), _config, PlayerStance.STAND, DT)
		_local_motor.simulate(_local, original, _config, PlayerStance.STAND, DT)
	var per_axis_error: float = 0.5 / InputCodec.MOVE_SCALE
	var angle_error: float = TAU / InputCodec.ANGLE_MAX
	var error_bound: float = 120.0 * DT * _config.sprint_speed * (sqrt(2.0) * per_axis_error + angle_error)
	assert_lt((_server.position - (_local.position - SEPARATION)).length(), error_bound)


func _sequence(tick: int) -> PlayerInput:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = tick
	inp.move = Vector2(0.6, 0.8) if tick < 90 else Vector2(0.0, 0.7)
	inp.yaw = float(tick) * 0.005
	inp.pitch = -0.23
	inp.buttons = PlayerInput.BTN_JUMP if tick == 60 else 0
	if tick >= 120:
		inp.buttons |= PlayerInput.BTN_SPRINT
	return inp


func _body(at: Vector3) -> CharacterBody3D:
	var body: CharacterBody3D = CharacterBody3D.new()
	body.position = at
	body.collision_layer = 2
	body.collision_mask = 1
	var collision: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	collision.shape = capsule
	collision.position.y = capsule.height * 0.5
	body.add_child(collision)
	_arena.add_child(body)
	return body
