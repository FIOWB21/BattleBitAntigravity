# Client-side half-RTT delay and independent loss for input and snapshots.
class_name PacketDelay
extends Node

signal packet_delivered(packet: PackedByteArray, extra: PackedByteArray)

const CAPACITY: int = 128
const USEC_PER_MS: float = 1000.0

class Slot extends RefCounted:
	var packet: PackedByteArray = PackedByteArray()
	var extra: PackedByteArray = PackedByteArray()
	var due: int = 0

var dropped: int = 0
var delivered: int = 0
var random: RandomNumberGenerator = RandomNumberGenerator.new()
var _slots: Array[Slot] = []
var _write: int = 0
var _read: int = 0
var _count: int = 0
var _packet_bytes: int = 0
var _extra_bytes: int = 0


func configure(packet_bytes: int, extra_bytes: int = 0) -> void:
	_packet_bytes = packet_bytes
	_extra_bytes = extra_bytes
	_slots.clear()
	for index: int in range(CAPACITY):
		var slot: Slot = Slot.new()
		slot.packet.resize(packet_bytes)
		slot.extra.resize(extra_bytes)
		_slots.append(slot)
	clear()


func clear() -> void:
	_read = 0
	_write = 0
	_count = 0
	dropped = 0
	delivered = 0


func submit(packet: PackedByteArray, extra: PackedByteArray = PackedByteArray()) -> bool:
	if packet.size() != _packet_bytes or extra.size() != _extra_bytes:
		return false
	if random.randf() * NetTimeSync.PERCENT < Net.time_sync.simulated_loss_percent:
		dropped += 1
		return false
	if Net.time_sync.simulated_rtt_ms == 0:
		delivered += 1
		packet_delivered.emit(packet, extra)
		return true
	if _count == _slots.size():
		dropped += 1
		return false
	var slot: Slot = _slots[_write]
	for index: int in range(packet.size()):
		slot.packet[index] = packet[index]
	for index: int in range(extra.size()):
		slot.extra[index] = extra[index]
	slot.due = Time.get_ticks_usec() + roundi(Net.time_sync.simulated_rtt_ms * USEC_PER_MS * 0.5)
	_write = (_write + 1) % _slots.size()
	_count += 1
	return true


func _process(_delta: float) -> void:
	flush(Time.get_ticks_usec())


func flush(now_usec: int) -> void:
	while _count > 0 and _slots[_read].due <= now_usec:
		var slot: Slot = _slots[_read]
		_read = (_read + 1) % _slots.size()
		_count -= 1
		delivered += 1
		packet_delivered.emit(slot.packet, slot.extra)
