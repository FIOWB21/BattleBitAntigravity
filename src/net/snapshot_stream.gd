# State transport belongs to the loaded world, never to individual input authorities.
class_name SnapshotStream
extends Node

signal snapshot_received(tick: int, last_processed_input_tick: int)
signal snapshot_sent(tick: int, player_count: int)

var players: NetworkPlayers
var last_received_tick: int = 0
var last_processed_input_tick: int = 0
var sent_packets: int = 0
var received_packets: int = 0
var received_bytes: int = 0
var _config: SnapshotConfig
var _actors: Array[Player] = []
var _weapon_ids: Dictionary[Weapon, int] = {}
var _packet: PackedByteArray = PackedByteArray()
var _state: PlayerSnapshot = PlayerSnapshot.new()
var _seen: Dictionary[int, bool] = {}
var _last_sent_tick: int = -1
var _owner_state: PredState = PredState.new()
var _owner_packet: PackedByteArray = PackedByteArray()
var delay: PacketDelay


func _ready() -> void:
	process_physics_priority = 100
	players.loader.map_loaded.connect(_map_loaded)
	_owner_packet.resize(PredState.WIRE_BYTES)
	delay = PacketDelay.new()
	delay.packet_delivered.connect(_accept_delayed)
	add_child(delay)


func _map_loaded(_map_id: String) -> void:
	_config = players.loader.current_data.snapshot_config
	_last_sent_tick = -1


func track(actor: Player) -> void:
	_actors.append(actor)
	_packet.resize(SnapshotCodec.packet_size(_actors.size()))
	actor.remote_view.configure(_config)
	delay.configure(_packet.size(), PredState.WIRE_BYTES)
	for slot: int in range(1, Loadout.SLOT_COUNT + 1):
		var weapon: Weapon = actor.inventory.weapon_at(slot)
		if weapon != null:
			_weapon_ids[weapon] = weapon.data.id.hash() & SnapshotCodec.UINT_MAX


func untrack(actor: Player) -> void:
	_actors.erase(actor)
	for slot: int in range(1, Loadout.SLOT_COUNT + 1):
		var weapon: Weapon = actor.inventory.weapon_at(slot)
		if weapon != null:
			_weapon_ids.erase(weapon)
	_packet.resize(SnapshotCodec.packet_size(_actors.size()))
	delay.configure(_packet.size(), PredState.WIRE_BYTES)


func reset() -> void:
	_config = null
	last_received_tick = 0
	last_processed_input_tick = 0
	sent_packets = 0
	received_packets = 0
	received_bytes = 0
	_last_sent_tick = -1
	_seen.clear()
	if delay != null:
		delay.clear()


func _physics_process(_delta: float) -> void:
	if _config == null or not Net.is_connected or not multiplayer.is_server() or _actors.is_empty():
		return
	if Net.tick <= _last_sent_tick or Net.tick % _config.interval_ticks != 0:
		return
	_last_sent_tick = Net.tick
	_packet.encode_u32(0, Net.tick)
	_packet.encode_u16(4, _actors.size())
	for index: int in range(_actors.size()):
		_capture(_actors[index])
		if not SnapshotCodec.encode_into(_state, _config, _packet,
				SnapshotCodec.HEADER_BYTES + index * SnapshotCodec.PLAYER_BYTES):
			return
		if not Game.is_dedicated and not _actors[index].is_local_player:
			_actors[index].remote_view.push_snapshot(_state)
	for recipient: Player in _actors:
		if recipient.network_owner_id == Net.SERVER_ID or not players.ready_peers.has(recipient.network_owner_id):
			continue
		_packet.encode_u32(6, recipient.server_sim.input_queue.last_input_tick)
		_owner_state.capture(recipient)
		_owner_state.encode_into(_owner_packet)
		receive_snapshot.rpc_id(recipient.network_owner_id, _packet, _owner_packet)
		sent_packets += 1
	snapshot_sent.emit(Net.tick, _actors.size())


func _capture(actor: Player) -> void:
	_state.tick = Net.tick
	_state.peer_id = actor.network_owner_id
	_state.position = actor.global_position
	_state.velocity = actor.velocity
	_state.yaw = actor.global_rotation.y
	_state.pitch = actor.head.rotation.x
	_state.flags = actor.stance
	if actor.is_on_floor():
		_state.flags |= PlayerSnapshot.GROUNDED
	if actor.motor.is_sprinting:
		_state.flags |= PlayerSnapshot.SPRINTING
	if actor.ads.target > 0.0:
		_state.flags |= PlayerSnapshot.AIMING
	if actor.weapon != null and actor.weapon.state == Weapon.State.RELOADING:
		_state.flags |= PlayerSnapshot.RELOADING
	if (actor.health_component as HealthComponent).is_dead:
		_state.flags |= PlayerSnapshot.DEAD
	if (actor.health_component as HealthComponent).is_downed:
		_state.flags |= PlayerSnapshot.DOWNED
	_state.weapon_id = _weapon_ids.get(actor.weapon, 0)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func receive_snapshot(packet: PackedByteArray, owner_packet: PackedByteArray = PackedByteArray()) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != Net.SERVER_ID:
		return
	delay.submit(packet, owner_packet)


func _accept_delayed(packet: PackedByteArray, owner_packet: PackedByteArray) -> void:
	accept_packet(packet, owner_packet)


func accept_packet(packet: PackedByteArray, owner_packet: PackedByteArray = PackedByteArray()) -> bool:
	if _config == null or not SnapshotCodec.valid_packet(packet, NetworkConfig.MAX_CLIENTS + 1):
		return false
	if not owner_packet.is_empty() and not _owner_state.decode_from(owner_packet):
		return false
	var tick: int = packet.decode_u32(0)
	if tick <= last_received_tick or not _validate_records(packet):
		return false
	last_received_tick = tick
	last_processed_input_tick = packet.decode_u32(6)
	received_packets += 1
	received_bytes += packet.size()
	for offset: int in range(SnapshotCodec.HEADER_BYTES, packet.size(), SnapshotCodec.PLAYER_BYTES):
		SnapshotCodec.decode_into(packet, offset, _config, _state)
		_state.tick = tick
		var actor: Player = players.actors.get(_state.peer_id)
		if actor != null and not actor.is_local_player:
			actor.remote_view.push_snapshot(_state)
		elif actor != null and not multiplayer.is_server() and not owner_packet.is_empty():
			actor.local_controller.prediction.receive(_owner_state, last_processed_input_tick, tick)
	snapshot_received.emit(tick, last_processed_input_tick)
	return true


func _validate_records(packet: PackedByteArray) -> bool:
	_seen.clear()
	for offset: int in range(SnapshotCodec.HEADER_BYTES, packet.size(), SnapshotCodec.PLAYER_BYTES):
		if not SnapshotCodec.decode_into(packet, offset, _config, _state) or _seen.has(_state.peer_id):
			return false
		_seen[_state.peer_id] = true
	return true
