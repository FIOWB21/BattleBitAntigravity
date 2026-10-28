# Fixed little-endian wire input: move i8/i8, angles u16/u16, buttons u16, tick u32.
class_name InputCodec
extends RefCounted

const FRAME_BYTES: int = 12
const MOVE_SCALE: float = 127.0
const ANGLE_MAX: int = 65535
const TICK_MAX: int = 0xffffffff
const BUTTON_MASK: int = (1 << 10) - 1
const MOVE_LIMIT: float = 1.01


static func valid(inp: PlayerInput) -> bool:
	return inp != null and inp.move.is_finite() and inp.move.length() <= MOVE_LIMIT \
		and is_finite(inp.yaw) and is_finite(inp.pitch) \
		and absf(inp.pitch) <= LocalInputReader.MAX_PITCH_RAD + PI / (2.0 * ANGLE_MAX) \
		and inp.tick > 0 and inp.tick <= TICK_MAX \
		and inp.buttons >= 0 and (inp.buttons & ~BUTTON_MASK) == 0


static func encode_into(inp: PlayerInput, bytes: PackedByteArray, offset: int = 0) -> bool:
	if not valid(inp) or offset < 0 or offset + FRAME_BYTES > bytes.size():
		return false
	bytes[offset] = roundi(clampf(inp.move.x, -1.0, 1.0) * MOVE_SCALE) & 0xff
	bytes[offset + 1] = roundi(clampf(inp.move.y, -1.0, 1.0) * MOVE_SCALE) & 0xff
	bytes.encode_u16(offset + 2, roundi(wrapf(inp.yaw, 0.0, TAU) / TAU * ANGLE_MAX))
	bytes.encode_u16(offset + 4, roundi((inp.pitch / PI + 0.5) * ANGLE_MAX))
	bytes.encode_u16(offset + 6, inp.buttons)
	bytes.encode_u32(offset + 8, inp.tick)
	return true


static func decode_into(bytes: PackedByteArray, offset: int, inp: PlayerInput) -> bool:
	if inp == null or offset < 0 or offset + FRAME_BYTES > bytes.size():
		return false
	var x: int = bytes[offset]
	var y: int = bytes[offset + 1]
	inp.move = Vector2(x if x < 128 else x - 256, y if y < 128 else y - 256) / MOVE_SCALE
	inp.yaw = float(bytes.decode_u16(offset + 2)) / ANGLE_MAX * TAU
	inp.pitch = (float(bytes.decode_u16(offset + 4)) / ANGLE_MAX - 0.5) * PI
	inp.buttons = bytes.decode_u16(offset + 6)
	inp.tick = bytes.decode_u32(offset + 8)
	if not valid(inp):
		return false
	inp.pitch = clampf(inp.pitch, -LocalInputReader.MAX_PITCH_RAD, LocalInputReader.MAX_PITCH_RAD)
	return true


static func copy_into(source: PlayerInput, target: PlayerInput) -> void:
	target.tick = source.tick
	target.move = source.move
	target.yaw = source.yaw
	target.pitch = source.pitch
	target.buttons = source.buttons
