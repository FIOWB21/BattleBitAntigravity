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

var _peer: ENetMultiplayerPeer
var _pending: Dictionary[int, Timer] = {}
var _closing: Dictionary[int, Timer] = {}
var _client_timeout: Timer


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_transport_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_client_timeout = Timer.new()
	_client_timeout.one_shot = true
	_client_timeout.timeout.connect(_on_connection_failed)
	add_child(_client_timeout)


func _physics_process(_delta: float) -> void:
	if _peer != null and multiplayer.is_server():
		tick += 1


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
	tick = 0
	last_error = ""
	is_connected = true
	Game.is_server = true
	if listen:
		nicknames[SERVER_ID] = local_nickname
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
	_client_timeout.start(config.handshake_timeout_seconds)
	return OK


func disconnect_all() -> void:
	_client_timeout.stop()
	for timer: Timer in _pending.values():
		timer.stop()
		timer.queue_free()
	for timer: Timer in _closing.values():
		timer.stop()
		timer.queue_free()
	_pending.clear()
	_closing.clear()
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
	disconnected.emit()


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_kick.bind(id, "hello_timeout"))
	add_child(timer)
	_pending[id] = timer
	timer.start(config.handshake_timeout_seconds)


func _on_peer_disconnected(id: int) -> void:
	_clear_timer(_pending, id)
	_clear_timer(_closing, id)
	if nicknames.erase(id):
		peer_left.emit(id)


func _on_transport_connected() -> void:
	hello.rpc_id(SERVER_ID, PROTOCOL_VERSION, local_nickname, password)


@rpc("any_peer", "call_remote", "reliable", 0)
func hello(version: int, nickname: String, supplied_password: String = "") -> void:
	if _peer == null or not multiplayer.is_server():
		return
	var id: int = multiplayer.get_remote_sender_id()
	if not _pending.has(id) or _closing.has(id):
		return
	var reason: String = HandshakeRules.rejection_reason(
		version, nickname, supplied_password, password, nicknames, config)
	if not reason.is_empty():
		_kick(id, reason)
		return
	_clear_timer(_pending, id)
	nicknames[id] = nickname
	welcome.rpc_id(id, id)
	Log.i("NET ACCEPT id=%d nickname=%s" % [id, nickname])
	peer_joined.emit(id, nickname)


@rpc("authority", "call_remote", "reliable", 0)
func welcome(id: int) -> void:
	if multiplayer.is_server() or is_connected:
		return
	if id != multiplayer.get_unique_id():
		return
	_client_timeout.stop()
	nicknames[id] = local_nickname
	is_connected = true
	Log.i("NET CONNECTED id=%d" % id)
	connected_to_server.emit()


@rpc("authority", "call_remote", "reliable", 0)
func kick(reason: String) -> void:
	if not multiplayer.is_server():
		_fail_connection.call_deferred(reason)


func _kick(id: int, reason: String) -> void:
	if _peer == null or _closing.has(id):
		return
	_clear_timer(_pending, id)
	kick.rpc_id(id, reason)
	Log.i("NET REJECT id=%d reason=%s" % [id, reason])
	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_finish_kick.bind(id))
	add_child(timer)
	_closing[id] = timer
	timer.start(config.kick_grace_seconds)


func _finish_kick(id: int) -> void:
	if _peer != null and multiplayer.get_peers().has(id):
		_peer.disconnect_peer(id)
	_on_peer_disconnected(id)


func _clear_timer(timers: Dictionary[int, Timer], id: int) -> void:
	if timers.has(id):
		timers[id].stop()
		timers[id].queue_free()
		timers.erase(id)


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
