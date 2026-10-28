# A preallocated ring of the last N wire frames; unused slots contain tick zero.
class_name InputHistory
extends RefCounted

var packet: PackedByteArray = PackedByteArray()
var _cursor: int = 0
var _last_tick: int = 0


func configure(count: int) -> void:
	packet.resize(count * InputCodec.FRAME_BYTES)
	packet.fill(0)
	_cursor = 0
	_last_tick = 0


func push(inp: PlayerInput) -> bool:
	if packet.is_empty() or inp.tick <= _last_tick:
		return false
	if not InputCodec.encode_into(inp, packet, _cursor):
		return false
	_last_tick = inp.tick
	_cursor = (_cursor + InputCodec.FRAME_BYTES) % packet.size()
	return true


func latest_into(inp: PlayerInput) -> bool:
	if packet.is_empty() or _last_tick == 0:
		return false
	return InputCodec.decode_into(packet, posmod(_cursor - InputCodec.FRAME_BYTES, packet.size()), inp)
