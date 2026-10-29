# Bounded, prewarmed outgoing RPC queue. Receivers keep their normal validation.
class_name NetSim
extends Node

signal packet_delivered(packet: PackedByteArray, extra: PackedByteArray, peer_id: int)

const CAPACITY: int = 128

class Slot extends RefCounted:
	var packet: PackedByteArray = PackedByteArray()
	var extra: PackedByteArray = PackedByteArray()
	var peer_id: int = 0
	var due: int = 0
	var sequence: int = 0
	var active: bool = false

var dropped: int = 0
var delivered: int = 0
var submitted: int = 0
var duplicated: int = 0
var reordered: int = 0
var overflowed: int = 0
var random: RandomNumberGenerator = RandomNumberGenerator.new()
var profile: NetSimConfig
var _slots: Array[Slot] = []
var _packet_bytes: int = 0
var _extra_bytes: int = 0
var _sequence: int = 0


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
	for slot: Slot in _slots:
		slot.active = false
	dropped = 0
	delivered = 0
	submitted = 0
	duplicated = 0
	reordered = 0
	overflowed = 0
	_sequence = 0


func discard_peer(peer_id: int) -> void:
	for slot: Slot in _slots:
		if slot.peer_id == peer_id:
			slot.active = false


func submit(packet: PackedByteArray, extra: PackedByteArray = PackedByteArray(),
		peer_id: int = 1, now_usec: int = -1) -> bool:
	if packet.size() != _packet_bytes or extra.size() != _extra_bytes or _slots.is_empty():
		return false
	var cfg: NetSimConfig = profile if profile != null else Net.time_sync.profile_for(peer_id)
	if not cfg.is_valid():
		return false
	submitted += 1
	if _chance(cfg.loss_percent):
		dropped += 1
		return false
	var now: int = Time.get_ticks_usec() if now_usec < 0 else now_usec
	var accepted: bool = _enqueue(packet, extra, peer_id, now, cfg)
	if accepted and _chance(cfg.duplicate_percent):
		if _enqueue(packet, extra, peer_id, now, cfg):
			duplicated += 1
	return accepted


func _enqueue(packet: PackedByteArray, extra: PackedByteArray, peer_id: int,
		now: int, cfg: NetSimConfig) -> bool:
	var delay_ms: float = maxf(0.0, cfg.rtt_ms * 0.5 + random.randf_range(-cfg.jitter_ms, cfg.jitter_ms))
	if _chance(cfg.reorder_percent):
		delay_ms += cfg.reorder_hold_ms
		reordered += 1
	if delay_ms == 0.0:
		delivered += 1
		packet_delivered.emit(packet, extra, peer_id)
		return true
	for slot: Slot in _slots:
		if slot.active:
			continue
		for index: int in range(packet.size()):
			slot.packet[index] = packet[index]
		for index: int in range(extra.size()):
			slot.extra[index] = extra[index]
		slot.peer_id = peer_id
		slot.due = now + roundi(delay_ms * NetSimConfig.USEC_PER_MS)
		slot.sequence = _sequence
		_sequence += 1
		slot.active = true
		return true
	dropped += 1
	overflowed += 1
	return false


func _chance(percent: float) -> bool:
	return percent > 0.0 and random.randf() * NetSimConfig.PERCENT < percent


func _process(_delta: float) -> void:
	flush(Time.get_ticks_usec())


func flush(now_usec: int) -> void:
	while true:
		var next: Slot = null
		for slot: Slot in _slots:
			if not slot.active or slot.due > now_usec:
				continue
			if next == null or slot.due < next.due or (slot.due == next.due and slot.sequence < next.sequence):
				next = slot
		if next == null:
			return
		next.active = false
		delivered += 1
		packet_delivered.emit(next.packet, next.extra, next.peer_id)
