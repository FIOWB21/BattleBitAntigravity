# ENet transport and admission. Gameplay replication is outside this component.
extends Node

signal peer_joined(id: int, nickname: String)
signal peer_left(id: int)
signal connected_to_server()
signal connection_failed()
signal disconnected()

const PROTOCOL_VERSION: int = NetworkConfig.PROTOCOL_VERSION
const DEFAULT_PORT: int = NetworkConfig.DEFAULT_PORT
const SERVER_ID: int = 1

@export var config: NetworkConfig = preload("res://src/net/default_network.tres")

var tick: int = 0
var nicknames: Dictionary[int, String] = {}
var local_nickname: String = "Player"
var password: String = ""
var last_error: String = ""
var is_connected: bool = false
var clock: NetClock = NetClock.new()
var time_sync: NetTimeSync = NetTimeSync.new()
var session: NetworkSession = NetworkSession.new()
var lifecycle: PeerLifecycle = PeerLifecycle.new()

var _peer: ENetMultiplayerPeer
var _client_timeout: Timer


func _ready() -> void:
	lifecycle.name = "PeerLifecycle"
	lifecycle.hello_expired.connect(_kick.bind("hello_timeout"))
	lifecycle.close_expired.connect(_finish_kick)
	lifecycle.peer_timed_out.connect(_on_peer_timeout)
	add_child(lifecycle)
	time_sync.name = "TimeSync"
	time_sync.setup(self, clock)
	time_sync.ping_updated.connect(_on_ping_updated)
	add_child(time_sync)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_transport_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_client_timeout = Timer.new()
	_client_timeout.one_shot = true
	_client_timeout.process_mode = Node.PROCESS_MODE_ALWAYS
	_client_timeout.ignore_time_scale = true
	_client_timeout.timeout.connect(_on_connection_failed)
	add_child(_client_timeout)


func _physics_process(delta: float) -> void:
	if _peer != null and multiplayer.is_server():
		tick += 1
	elif is_connected:
		tick = clock.advance(delta, Time.get_ticks_usec())


func _on_ping_updated(measured_ms: float) -> void:
	Game.debug["ping_ms"] = measured_ms


func start_server(port: int, max_clients: int, listen: bool = true) -> Error:
	if _peer != null:
		return ERR_ALREADY_IN_USE
	if not NetworkConfig.valid_port(port) or not NetworkConfig.valid_max_clients(max_clients):
		return ERR_INVALID_PARAMETER
	if listen and not HandshakeRules.valid_nickname(local_nickname, config):
		return ERR_INVALID_PARAMETER
	var candidate: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var result: Error = candidate.create_server(port, max_clients, NetworkConfig.CHANNEL_COUNT)
	if result != OK:
		candidate.close()
		return result
	_peer = candidate
	multiplayer.multiplayer_peer = _peer
	session.configure(config.blocked_ips)
	lifecycle.configure(config)
	tick = 0
	last_error = ""
	is_connected = true
	Game.is_server = true
	if listen:
		nicknames[SERVER_ID] = local_nickname
		session.admit(SERVER_ID, local_nickname)
		peer_joined.emit(SERVER_ID, local_nickname)
	return OK


func join(address: String, port: int) -> Error:
	if _peer != null:
		return ERR_ALREADY_IN_USE
	if address.strip_edges().is_empty() or not NetworkConfig.valid_port(port):
		return ERR_INVALID_PARAMETER
	if not HandshakeRules.valid_nickname(local_nickname, config):
		return ERR_INVALID_PARAMETER
	var candidate: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var result: Error = candidate.create_client(address, port, NetworkConfig.CHANNEL_COUNT)
	if result != OK:
		candidate.close()
		return result
	_peer = candidate
	multiplayer.multiplayer_peer = _peer
	last_error = ""
	is_connected = false
	Game.is_server = false
	lifecycle.configure(config)
	_client_timeout.start(config.handshake_timeout_seconds)
	return OK


func disconnect_all() -> void:
	time_sync.stop()
	_client_timeout.stop()
	lifecycle.clear()
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var departed: Array[int] = nicknames.keys()
	nicknames.clear()
	is_connected = false
	tick = 0
	Game.is_server = Game.is_dedicated
	for id: int in departed:
		peer_left.emit(id)
	session.clear()
	disconnected.emit()


func _on_peer_connected(id: int) -> void:
	# On clients, relayed player IDs have no direct ENetPacketPeer.
	if not multiplayer.is_server() and id != SERVER_ID:
		return
	PeerLifecycle.configure_transport(_peer.get_peer(id), config)
	if not multiplayer.is_server():
		return
	lifecycle.watch(id, config.handshake_timeout_seconds)
	if session.is_blocked(peer_ip(id)):
		_kick(id, "ip_banned")


func _on_peer_disconnected(id: int) -> void:
	lifecycle.forget(id)
	_revoke(id)


func _revoke(id: int) -> void:
	if nicknames.erase(id):
		peer_left.emit(id)
	session.forget(id)


func _on_transport_connected() -> void:
	hello.rpc_id(SERVER_ID, PROTOCOL_VERSION, local_nickname, password)


@rpc("any_peer", "call_remote", "reliable", 0)
func hello(version: int, nickname: String, supplied_password: String = "") -> void:
	if _peer == null or not multiplayer.is_server():
		return
	var id: int = multiplayer.get_remote_sender_id()
	if not lifecycle.pending.has(id) or lifecycle.closing.has(id):
		return
	var reason: String = HandshakeRules.rejection_reason(
		version, nickname, supplied_password, password, nicknames, config)
	if not reason.is_empty():
		_kick(id, reason)
		return
	lifecycle.accepted(id)
	nicknames[id] = nickname
	session.admit(id, nickname)
	lifecycle.track(id, Time.get_ticks_usec())
	welcome.rpc_id(id, id, Game.map_id)
	Log.i("NET ACCEPT id=%d nickname=%s" % [id, nickname])
	peer_joined.emit(id, nickname)


@rpc("authority", "call_remote", "reliable", 0)
func welcome(id: int, map_id: String = "testbed") -> void:
	if multiplayer.is_server() or is_connected:
		return
	if id != multiplayer.get_unique_id():
		return
	_client_timeout.stop()
	nicknames[id] = local_nickname
	Game.map_id = map_id
	is_connected = true
	lifecycle.track(SERVER_ID, Time.get_ticks_usec())
	Log.i("NET CONNECTED id=%d" % id)
	time_sync.start()
	connected_to_server.emit()


@rpc("authority", "call_remote", "reliable", 0)
func kick(reason: String) -> void:
	if not multiplayer.is_server():
		_fail_connection.call_deferred(reason)


func _kick(id: int, reason: String) -> void:
	if _peer == null or lifecycle.closing.has(id):
		return
	lifecycle.close(id, config.kick_grace_seconds)
	if time_sync.can_send(id):
		kick.rpc_id(id, reason)
	Log.i("NET REJECT id=%d reason=%s" % [id, reason])
	_revoke(id)


func _finish_kick(id: int) -> void:
	if _peer != null and multiplayer.get_peers().has(id):
		# Remove high-level replication/cache recipients before closing ENet channels.
		(multiplayer as SceneMultiplayer).disconnect_peer(id)
	_on_peer_disconnected(id)


func _on_connection_failed() -> void:
	_fail_connection("connection_failed")


func _on_server_disconnected() -> void:
	_fail_connection("server_disconnected")


func _fail_connection(reason: String) -> void:
	if _peer == null:
		return
	last_error = reason
	disconnect_all()
	Log.i("NET FAILED reason=%s" % reason)
	connection_failed.emit()


func disconnect_with_error(reason: String) -> void:
	_fail_connection(reason)


func remove_peer(id: int, reason: String) -> bool:
	if not multiplayer.is_server() or _peer == null or id <= SERVER_ID \
			or not nicknames.has(id) or lifecycle.closing.has(id):
		return false
	_kick(id, reason)
	return true


func peer_ip(id: int) -> String:
	if _peer == null or not multiplayer.get_peers().has(id) \
			or (not multiplayer.is_server() and id != SERVER_ID):
		return ""
	return _peer.get_peer(id).get_remote_address()


func ban_ip(address: String) -> bool:
	if _peer == null or not multiplayer.is_server() or not session.ban_ip(address):
		return false
	for id: int in multiplayer.get_peers():
		if session.is_blocked(peer_ip(id)):
			_kick(id, "ip_banned")
	return true


func note_packet(id: int) -> void:
	lifecycle.received(id, Time.get_ticks_usec())


func _on_peer_timeout(id: int) -> void:
	if multiplayer.is_server():
		Log.i("NET TIMEOUT id=%d" % id)
		_finish_kick(id)
	else:
		_fail_connection("server_timeout")
