# Little-endian header: tick u32, count u16, recipient's input acknowledgement u32.
# Record: peer u32, position 3*u16, velocity 3*u16, angles 2*u16, flags u8, weapon u32.
class_name SnapshotCodec
extends RefCounted

const HEADER_BYTES: int = 10
const PLAYER_BYTES: int = 25
const QUANT_MAX: int = 65535
const UINT_MAX: int = 0xffffffff


static func packet_size(count: int) -> int:
	return HEADER_BYTES + count * PLAYER_BYTES


static func valid_packet(bytes: PackedByteArray, max_players: int) -> bool:
	if bytes.size() < HEADER_BYTES or bytes.decode_u32(0) == 0:
		return false
	var count: int = bytes.decode_u16(4)
	return count > 0 and count <= max_players and bytes.size() == packet_size(count)


static func encode_into(s: PlayerSnapshot, cfg: SnapshotConfig, bytes: PackedByteArray, at: int = 0) -> bool:
	if not _valid_state(s) or cfg == null or at < 0 or at + PLAYER_BYTES > bytes.size():
		return false
	bytes.encode_u32(at, s.peer_id)
	for axis: int in range(3):
		bytes.encode_u16(at + 4 + axis * 2,
			quantize(s.position[axis], cfg.position_min[axis], cfg.position_max[axis]))
		bytes.encode_u16(at + 10 + axis * 2,
			quantize(s.velocity[axis], -cfg.velocity_limit, cfg.velocity_limit))
	bytes.encode_u16(at + 16, quantize(wrapf(s.yaw, -PI, PI), -PI, PI))
	bytes.encode_u16(at + 18, quantize(s.pitch, -PI * 0.5, PI * 0.5))
	bytes[at + 20] = s.flags
	bytes.encode_u32(at + 21, s.weapon_id)
	return true


static func decode_into(bytes: PackedByteArray, at: int, cfg: SnapshotConfig, s: PlayerSnapshot) -> bool:
	if s == null or cfg == null or at < 0 or at + PLAYER_BYTES > bytes.size():
		return false
	s.peer_id = bytes.decode_u32(at)
	for axis: int in range(3):
		s.position[axis] = dequantize(bytes.decode_u16(at + 4 + axis * 2),
			cfg.position_min[axis], cfg.position_max[axis])
		s.velocity[axis] = dequantize(bytes.decode_u16(at + 10 + axis * 2),
			-cfg.velocity_limit, cfg.velocity_limit)
	s.yaw = dequantize(bytes.decode_u16(at + 16), -PI, PI)
	s.pitch = dequantize(bytes.decode_u16(at + 18), -PI * 0.5, PI * 0.5)
	s.flags = bytes[at + 20]
	s.weapon_id = bytes.decode_u32(at + 21)
	return _valid_state(s)


static func quantize(value: float, lower: float, upper: float) -> int:
	return roundi(clampf((value - lower) / (upper - lower), 0.0, 1.0) * QUANT_MAX)


static func dequantize(value: int, lower: float, upper: float) -> float:
	return lerpf(lower, upper, float(value) / QUANT_MAX)


static func _valid_state(s: PlayerSnapshot) -> bool:
	return s != null and s.peer_id > 0 and s.peer_id <= 0x7fffffff \
		and s.position.is_finite() and s.velocity.is_finite() \
		and is_finite(s.yaw) and is_finite(s.pitch) and absf(s.pitch) <= PI * 0.5 \
		and s.flags >= 0 and (s.flags & ~PlayerSnapshot.FLAG_MASK) == 0 \
		and (s.flags & PlayerSnapshot.STANCE_MASK) <= PlayerStance.PRONE \
		and s.weapon_id >= 0 and s.weapon_id <= UINT_MAX
