extends GutTest

const MOVE_ERROR: float = 0.5 / InputCodec.MOVE_SCALE + 0.000001
const ANGLE_ERROR: float = TAU / InputCodec.ANGLE_MAX + 0.000001


func test_wire_layout_is_exactly_twelve_little_endian_bytes() -> void:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 0x12345678
	inp.move = Vector2(-1.0, 0.0)
	inp.buttons = PlayerInput.BTN_FIRE | PlayerInput.BTN_INTERACT
	var bytes: PackedByteArray = _buffer()
	assert_true(InputCodec.encode_into(inp, bytes))
	assert_eq(bytes.size(), 12)
	assert_eq(bytes[0], 129)
	assert_eq(bytes[1], 0)
	assert_eq(bytes.decode_u16(2), 0)
	assert_eq(bytes.decode_u16(4), 32768)
	assert_eq(bytes.decode_u16(6), inp.buttons)
	assert_eq(bytes.decode_u32(8), 0x12345678)
	assert_eq(bytes[8], 0x78)
	assert_eq(bytes[11], 0x12)


func test_round_trip_angles_directions_buttons_and_uint32_edges() -> void:
	var inp: PlayerInput = PlayerInput.new()
	var decoded: PlayerInput = PlayerInput.new()
	var bytes: PackedByteArray = _buffer()
	for index: int in range(720):
		inp.tick = InputCodec.TICK_MAX if index == 719 else index + 1
		inp.move = Vector2.from_angle(float(index) * 0.137) * float(index % 11) / 10.0
		inp.yaw = float(index - 360) * 0.731
		inp.pitch = lerpf(-LocalInputReader.MAX_PITCH_RAD, LocalInputReader.MAX_PITCH_RAD, float(index) / 719.0)
		inp.buttons = index % (InputCodec.BUTTON_MASK + 1)
		assert_true(InputCodec.encode_into(inp, bytes))
		assert_true(InputCodec.decode_into(bytes, 0, decoded))
		assert_almost_eq(decoded.move.x, inp.move.x, MOVE_ERROR)
		assert_almost_eq(decoded.move.y, inp.move.y, MOVE_ERROR)
		assert_lte(absf(angle_difference(decoded.yaw, inp.yaw)), ANGLE_ERROR)
		assert_almost_eq(decoded.pitch, inp.pitch, ANGLE_ERROR)
		assert_eq(decoded.buttons, inp.buttons)
		assert_eq(decoded.tick, inp.tick)


func test_invalid_data_and_truncated_frames_are_rejected_without_errors() -> void:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	var bytes: PackedByteArray = _buffer()
	for invalid_move: Vector2 in [Vector2.ONE, Vector2(INF, 0.0), Vector2(NAN, 0.0)]:
		inp.move = invalid_move
		assert_false(InputCodec.encode_into(inp, bytes))
	inp.move = Vector2.ZERO
	inp.yaw = NAN
	assert_false(InputCodec.encode_into(inp, bytes))
	inp.yaw = 0.0
	inp.pitch = PI * 0.5
	assert_false(InputCodec.encode_into(inp, bytes))
	inp.pitch = 0.0
	inp.buttons = 1 << 15
	assert_false(InputCodec.encode_into(inp, bytes))
	inp.buttons = 0
	for tick: int in [0, -1, InputCodec.TICK_MAX + 1]:
		inp.tick = tick
		assert_false(InputCodec.encode_into(inp, bytes))
	assert_false(InputCodec.decode_into(PackedByteArray([1, 2]), 0, inp))
	assert_false(InputCodec.decode_into(bytes, -1, inp))
	assert_false(InputCodec.decode_into(bytes, 1, inp))
	assert_false(InputCodec.encode_into(null, bytes))


func test_malicious_wire_direction_pitch_and_buttons_are_validated_after_decode() -> void:
	var bytes: PackedByteArray = _buffer()
	var inp: PlayerInput = PlayerInput.new()
	bytes.encode_u32(8, 1)
	bytes.encode_u16(4, 32768)
	bytes[0] = 127
	bytes[1] = 127
	assert_false(InputCodec.decode_into(bytes, 0, inp))
	bytes[1] = 0
	assert_true(InputCodec.decode_into(bytes, 0, inp))
	bytes.encode_u16(4, 65535)
	assert_false(InputCodec.decode_into(bytes, 0, inp))
	bytes.encode_u16(4, 32768)
	bytes.encode_u16(6, 1 << 15)
	assert_false(InputCodec.decode_into(bytes, 0, inp))


func test_history_keeps_last_n_unique_frames_without_resizing() -> void:
	var history: InputHistory = InputHistory.new()
	history.configure(6)
	var decoded: PlayerInput = PlayerInput.new()
	var inp: PlayerInput = PlayerInput.new()
	for tick: int in range(1, 21):
		inp.tick = tick
		assert_true(history.push(inp))
		assert_eq(history.packet.size(), 72)
	assert_false(history.push(inp))
	var ticks: Array[int] = []
	for offset: int in range(0, history.packet.size(), InputCodec.FRAME_BYTES):
		assert_true(InputCodec.decode_into(history.packet, offset, decoded))
		ticks.append(decoded.tick)
	ticks.sort()
	assert_eq(ticks, [15, 16, 17, 18, 19, 20])


func test_reusable_reader_preserves_existing_commands_and_clears_one_shots() -> void:
	var reader: LocalInputReader = LocalInputReader.new()
	var inp: PlayerInput = PlayerInput.new()
	var event: InputEventAction = InputEventAction.new()
	event.action = InputActions.THROW_GRENADE
	event.pressed = true
	reader.handle_input_event(event)
	reader.read_into(inp)
	assert_eq(inp.tick, 1)
	assert_true(inp.throw_grenade)
	reader.read_into(inp)
	assert_eq(inp.tick, 2)
	assert_false(inp.throw_grenade)


func _buffer() -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(InputCodec.FRAME_BYTES)
	return bytes
