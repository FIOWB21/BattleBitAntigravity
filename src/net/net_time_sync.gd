# Low-rate clock probes; PacketDelay uses the same net_sim settings for gameplay.
class_name NetTimeSync
extends Node

signal ping_updated(measured_ms: float)

const SERVER_ID: int = 1
const NO_PROBE: int = -1
const PERCENT: float = 100.0

var simulated_rtt_ms: int = 0
var simulated_loss_percent: float = 0.0
var probe_count: int = 0

var _net: Node
var _clock: NetClock
var _interval: Timer
var _outbound: Timer
var _inbound: Timer
var _pending: Dictionary[int, int] = {}
var _outbound_due: Dictionary[int, int] = {}
var _inbound_due: Dictionary[int, int] = {}
var _active: bool = false
var _random: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(net: Node, clock: NetClock) -> void:
	_net = net
	_clock = clock


func _ready() -> void:
	_interval = _make_timer(_send_probe, false)
	_outbound = _make_timer(_transmit_pings)
	_inbound = _make_timer(_accept_pong)
	_random.randomize()


func start() -> void:
	stop()
	_clock.configure(_net.config, Engine.physics_ticks_per_second)
	_active = true
	_interval.start(_net.config.ping_interval_seconds)
	_send_probe()


func stop() -> void:
	_active = false
	_pending.clear()
	_outbound_due.clear()
	_inbound_due.clear()
	probe_count = 0
	if _interval != null:
		_interval.stop()
		_outbound.stop()
		_inbound.stop()
	_clock.reset()
	ping_updated.emit(0.0)


func configure_simulation(rtt_ms: int, loss_percent: float) -> void:
	simulated_rtt_ms = maxi(rtt_ms, 0)
	simulated_loss_percent = clampf(loss_percent, 0.0, PERCENT)


func _make_timer(callback: Callable, one_shot: bool = true) -> Timer:
	var timer: Timer = Timer.new()
	timer.one_shot = one_shot
	timer.timeout.connect(callback)
	add_child(timer)
	return timer


func _send_probe() -> void:
	if not _active or not _net.is_connected:
		return
	var now: int = Time.get_ticks_usec()
	_expire_probes(now)
	_pending[now] = NO_PROBE
	probe_count += 1
	if _dropped():
		return
	if simulated_rtt_ms > 0:
		_outbound_due[now] = now + _one_way_delay_usec()
		_schedule(_outbound, _outbound_due)
	else:
		if _can_send(SERVER_ID):
			ping.rpc_id(SERVER_ID, now)


func _transmit_pings() -> void:
	if not _active or not _net.is_connected or _outbound_due.is_empty():
		return
	var now: int = maxi(Time.get_ticks_usec(), int(_outbound_due.values().min()))
	for token: int in _outbound_due.keys():
		if _outbound_due[token] <= now:
			if _pending.has(token) and _can_send(SERVER_ID):
				ping.rpc_id(SERVER_ID, token)
			_outbound_due.erase(token)
	_schedule(_outbound, _outbound_due)


@rpc("any_peer", "call_remote", "unreliable", 0)
func ping(client_time: int) -> void:
	if not multiplayer.is_server() or not _net.is_connected:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if _net.nicknames.has(sender) and _can_send(sender):
		pong.rpc_id(sender, client_time, _net.tick)


func _can_send(peer_id: int) -> bool:
	var transport: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if transport == null or not multiplayer.get_peers().has(peer_id):
		return false
	var peer: ENetPacketPeer = transport.get_peer(peer_id)
	return peer != null and peer.get_state() == ENetPacketPeer.STATE_CONNECTED and peer.get_channels() > 0


@rpc("authority", "call_remote", "unreliable", 0)
func pong(client_time: int, server_tick: int) -> void:
	if not _active or not _net.is_connected or multiplayer.is_server():
		return
	if not _pending.has(client_time) or _pending[client_time] != NO_PROBE or server_tick < 0:
		return
	if _dropped():
		return
	_pending[client_time] = server_tick
	if simulated_rtt_ms > 0:
		_inbound_due[client_time] = Time.get_ticks_usec() + _one_way_delay_usec()
		_schedule(_inbound, _inbound_due)
	else:
		_record_pong(client_time)


func _accept_pong() -> void:
	if not _active or _inbound_due.is_empty():
		return
	var now: int = maxi(Time.get_ticks_usec(), int(_inbound_due.values().min()))
	for token: int in _inbound_due.keys():
		if _inbound_due[token] <= now:
			_record_pong(token)
			_inbound_due.erase(token)
	_schedule(_inbound, _inbound_due)


func _record_pong(token: int) -> void:
	if not _pending.has(token):
		return
	if _clock.record_pong(token, Time.get_ticks_usec(), _pending[token]):
		ping_updated.emit(_clock.rtt_seconds * NetClock.MS_PER_SECOND)
	_pending.erase(token)


func _expire_probes(now_usec: int) -> void:
	for token: int in _pending.keys():
		if float(now_usec - token) / NetClock.USEC_PER_SECOND >= _net.config.ping_timeout_seconds:
			_pending.erase(token)
			_outbound_due.erase(token)
			_inbound_due.erase(token)


func _schedule(timer: Timer, deadlines: Dictionary[int, int]) -> void:
	if deadlines.is_empty():
		timer.stop()
		return
	var earliest: int = deadlines.values().min()
	var seconds: float = float(earliest - Time.get_ticks_usec()) / NetClock.USEC_PER_SECOND
	timer.start(maxf(seconds, 1.0 / NetClock.USEC_PER_SECOND))


func _one_way_delay_usec() -> int:
	return roundi(float(simulated_rtt_ms) / NetClock.MS_PER_SECOND * 0.5 * NetClock.USEC_PER_SECOND)


func _dropped() -> bool:
	return _random.randf() * PERCENT < simulated_loss_percent
