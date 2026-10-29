# Timers are created only on connection transitions, never during simulation.
class_name PeerLifecycle
extends Node

signal hello_expired(peer: int)
signal close_expired(peer: int)
signal peer_timed_out(peer: int)

var pending: Dictionary[int, Timer] = {}
var closing: Dictionary[int, Timer] = {}
var activity: Dictionary[int, int] = {}
var _timeout_usec: int = 0
var _watchdog: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_watchdog = Timer.new()
	_watchdog.ignore_time_scale = true
	_watchdog.timeout.connect(func() -> void: expire(Time.get_ticks_usec()))
	add_child(_watchdog)


func configure(config: NetworkConfig) -> void:
	clear()
	_timeout_usec = ceili(config.client_timeout_seconds * NetClock.USEC_PER_SECOND)
	_watchdog.start(config.activity_poll_seconds)


func track(peer: int, now_usec: int) -> void:
	activity[peer] = now_usec


func received(peer: int, now_usec: int) -> void:
	if activity.has(peer):
		activity[peer] = maxi(activity[peer], now_usec)


func expire(now_usec: int) -> void:
	for peer: int in activity.keys():
		if activity.has(peer) and now_usec - activity[peer] >= _timeout_usec:
			activity.erase(peer)
			peer_timed_out.emit(peer)


static func configure_transport(peer: ENetPacketPeer, config: NetworkConfig) -> void:
	var timeout_ms: int = ceili(config.client_timeout_seconds * NetClock.MS_PER_SECOND)
	peer.set_timeout(config.timeout_factor, timeout_ms, timeout_ms)
	peer.ping_interval(ceili(config.ping_interval_seconds * NetClock.MS_PER_SECOND))


func watch(peer: int, seconds: float) -> void:
	_start(pending, peer, seconds, hello_expired.emit.bind(peer))


func close(peer: int, seconds: float) -> void:
	accepted(peer)
	activity.erase(peer)
	_start(closing, peer, seconds, close_expired.emit.bind(peer))


func accepted(peer: int) -> void:
	_clear_timer(pending, peer)


func forget(peer: int) -> void:
	activity.erase(peer)
	_clear_timer(pending, peer)
	_clear_timer(closing, peer)


func clear() -> void:
	activity.clear()
	if _watchdog != null:
		_watchdog.stop()
	for peer: int in pending.keys():
		_clear_timer(pending, peer)
	for peer: int in closing.keys():
		_clear_timer(closing, peer)


func _start(timers: Dictionary[int, Timer], peer: int, seconds: float, callback: Callable) -> void:
	_clear_timer(timers, peer)
	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.ignore_time_scale = true
	timer.timeout.connect(callback)
	add_child(timer)
	timers[peer] = timer
	timer.start(seconds)


func _clear_timer(timers: Dictionary[int, Timer], peer: int) -> void:
	if timers.has(peer):
		timers[peer].stop()
		timers[peer].queue_free()
		timers.erase(peer)
