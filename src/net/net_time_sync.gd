# Clock probes use the outgoing simulator; received packets are immediate.
class_name NetTimeSync
extends Node

signal ping_updated(measured_ms: float)

const SERVER_ID: int = 1
const NO_PROBE: int = -1
const PERCENT: float = NetSimConfig.PERCENT
const PROBE_BYTES: int = 16

var profile: NetSimConfig = preload("res://src/net/default_net_sim.tres").duplicate() as NetSimConfig
var simulated_rtt_ms: int:
	get: return profile.rtt_ms
var simulated_loss_percent: float:
	get: return profile.loss_percent
var probe_count: int = 0
var outbound: NetSim
var _net: Node
var _clock: NetClock
var _interval: Timer
var _pending: Dictionary[int, int] = {}
var _profiles: Dictionary[int, NetSimConfig] = {}
var _packet: PackedByteArray = PackedByteArray()
var _active: bool = false
var _server_override: bool = false


func setup(net: Node, clock: NetClock) -> void:
	_net = net
	_clock = clock
	_net.peer_left.connect(_peer_left)


func _ready() -> void:
	_interval = Timer.new()
	_interval.timeout.connect(_send_probe)
	add_child(_interval)
	outbound = NetSim.new()
	outbound.configure(PROBE_BYTES)
	outbound.packet_delivered.connect(_transmit)
	add_child(outbound)
	_packet.resize(PROBE_BYTES)


func start() -> void:
	stop()
	_clock.configure(_net.config, Engine.physics_ticks_per_second)
	_active = true
	_advertise()
	_interval.start(_net.config.ping_interval_seconds)
	_send_probe()


func stop() -> void:
	_active = false
	_pending.clear()
	_profiles.clear()
	_server_override = false
	probe_count = 0
	if _interval != null:
		_interval.stop()
		outbound.clear()
	_clock.reset()
	ping_updated.emit(0.0)


func configure_simulation(rtt_ms: int, loss_percent: float, jitter_ms: int = 0,
		duplicate_percent: float = 0.0, reorder_percent: float = 0.0) -> void:
	var candidate: NetSimConfig = NetSimConfig.new()
	candidate.rtt_ms = rtt_ms
	candidate.loss_percent = loss_percent
	candidate.jitter_ms = jitter_ms
	candidate.duplicate_percent = duplicate_percent
	candidate.reorder_percent = reorder_percent
	if not candidate.is_valid():
		return
	profile = candidate
	_server_override = _net.is_connected and multiplayer.is_server()
	_advertise()


func profile_for(peer_id: int) -> NetSimConfig:
	if multiplayer.is_server() and not _server_override:
		return _profiles.get(peer_id, profile)
	return profile


func _advertise() -> void:
	if _net.is_connected and not multiplayer.is_server() and can_send(SERVER_ID):
		set_simulation.rpc_id(SERVER_ID, profile.rtt_ms, profile.loss_percent,
			profile.jitter_ms, profile.duplicate_percent, profile.reorder_percent)


@rpc("any_peer", "call_remote", "reliable", 0)
func set_simulation(rtt_ms: int, loss: float, jitter_ms: int, duplicates: float, reorder: float) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or not _net.nicknames.has(sender):
		return
	_net.note_packet(sender)
	var cfg: NetSimConfig = NetSimConfig.new()
	cfg.rtt_ms = rtt_ms
	cfg.loss_percent = loss
	cfg.jitter_ms = jitter_ms
	cfg.duplicate_percent = duplicates
	cfg.reorder_percent = reorder
	if cfg.is_valid():
		_profiles[sender] = cfg


func _peer_left(peer_id: int) -> void:
	_profiles.erase(peer_id)
	if outbound != null:
		outbound.discard_peer(peer_id)


func _send_probe() -> void:
	if not _active or not _net.is_connected:
		return
	var now: int = Time.get_ticks_usec()
	_expire_probes(now)
	_pending[now] = NO_PROBE
	probe_count += 1
	_packet.encode_s64(0, now)
	_packet.encode_s64(8, 0)
	outbound.submit(_packet)


func _transmit(packet: PackedByteArray, _extra: PackedByteArray, peer_id: int) -> void:
	if not _net.is_connected or not can_send(peer_id):
		return
	if multiplayer.is_server():
		if _net.nicknames.has(peer_id):
			pong.rpc_id(peer_id, packet.decode_s64(0), packet.decode_s64(8))
	elif _active and _pending.has(packet.decode_s64(0)):
		ping.rpc_id(peer_id, packet.decode_s64(0))


@rpc("any_peer", "call_remote", "unreliable", 0)
func ping(client_time: int) -> void:
	if not multiplayer.is_server() or not _net.is_connected:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if _net.nicknames.has(sender) and can_send(sender):
		_net.note_packet(sender)
		_packet.encode_s64(0, client_time)
		_packet.encode_s64(8, _net.tick)
		outbound.submit(_packet, PackedByteArray(), sender)


func can_send(peer_id: int) -> bool:
	var transport: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if transport == null or not multiplayer.get_peers().has(peer_id):
		return false
	var peer: ENetPacketPeer = transport.get_peer(peer_id)
	return peer != null and peer.get_state() == ENetPacketPeer.STATE_CONNECTED and peer.get_channels() > 0


@rpc("authority", "call_remote", "unreliable", 0)
func pong(client_time: int, server_tick: int) -> void:
	if not _active or not _net.is_connected or multiplayer.is_server():
		return
	if not _pending.has(client_time) or server_tick < 0:
		return
	_net.note_packet(SERVER_ID)
	if _clock.record_pong(client_time, Time.get_ticks_usec(), server_tick):
		ping_updated.emit(_clock.rtt_seconds * NetClock.MS_PER_SECOND)
	_pending.erase(client_time)


func _expire_probes(now_usec: int) -> void:
	for token: int in _pending.keys():
		if float(now_usec - token) / NetClock.USEC_PER_SECOND >= _net.config.ping_timeout_seconds:
			_pending.erase(token)
