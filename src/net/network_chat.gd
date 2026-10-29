# The sender and team are derived exclusively from admitted server actors.
class_name NetworkChat
extends Node

signal message_received(sender: int, nickname: String, text: String, team_only: bool)
signal notice_received(text: String)

@export var config: ChatConfig = preload("res://src/net/default_chat.tres")

var loader: MapLoader
var policy: ChatPolicy = ChatPolicy.new()
var admin: ChatAdmin = ChatAdmin.new()


func _ready() -> void:
	Net.peer_left.connect(_forget)
	Net.disconnected.connect(reset)


func send(text: String, team_only: bool = false) -> void:
	if not Net.is_connected:
		return
	if multiplayer.is_server():
		_accept(multiplayer.get_unique_id(), text, team_only)
	else:
		submit.rpc_id(Net.SERVER_ID, text, team_only)


@rpc("any_peer", "call_remote", "reliable", 0)
func submit(text: String, team_only: bool) -> void:
	if multiplayer.is_server():
		_accept(multiplayer.get_remote_sender_id(), text, team_only)


func _accept(sender: int, raw: String, team_only: bool) -> void:
	if not multiplayer.is_server() or not Net.nicknames.has(sender) \
			or not loader.players.ready_peers.has(sender) or not loader.players.actors.has(sender):
		return
	Net.note_packet(sender)
	if not policy.allow(sender, Time.get_ticks_usec(), config):
		return
	if raw.length() > config.max_request_length:
		_notice(sender, "Message is too long.")
		return
	if raw.strip_edges().begins_with("/"):
		_command(sender, raw.strip_edges())
		return
	var text: String = ChatPolicy.sanitize(raw, config.max_length)
	if text.is_empty():
		return
	for recipient: int in recipients(sender, team_only):
		_deliver(recipient, sender, Net.nicknames[sender], text, team_only)


func recipients(sender: int, team_only: bool) -> Array[int]:
	var result: Array[int] = []
	var actor: Player = loader.players.actors.get(sender)
	if actor == null:
		return result
	for id: int in loader.players.ready_peers:
		var target: Player = loader.players.actors.get(id)
		if Net.nicknames.has(id) and target != null \
				and (not team_only or (actor.team_id > 0 and target.team_id == actor.team_id)):
			result.append(id)
	return result


func _deliver(recipient: int, sender: int, nickname: String, text: String, team_only: bool) -> void:
	if recipient == multiplayer.get_unique_id():
		message_received.emit(sender, nickname, text, team_only)
	else:
		deliver.rpc_id(recipient, sender, nickname, text, team_only)


@rpc("authority", "call_remote", "reliable", 0)
func deliver(sender: int, nickname: String, text: String, team_only: bool) -> void:
	if not multiplayer.is_server():
		Net.note_packet(Net.SERVER_ID)
		message_received.emit(sender, nickname, text, team_only)


func _command(sender: int, raw: String) -> void:
	var command: String = raw.get_slice(" ", 0)
	var argument: String = raw.substr(command.length()).strip_edges()
	if command == "/admin":
		var accepted: bool = admin.login(sender, argument, Game.admin_password)
		_notice(sender, "Admin authenticated." if accepted else "Admin authentication failed.")
		return
	if not admin.is_authorized(sender, Game.admin_password):
		_notice(sender, "Admin authentication required: /admin <password>")
		return
	match command:
		"/kick":
			_kick(sender, argument)
		"/ban":
			_ban(sender, argument)
		"/unban":
			_notice(sender, "IP removed." if Net.session.unban_ip(argument) else "Unknown IP.")
		"/blacklist":
			_notice(sender, "Blocked IPs: " + ", ".join(Net.session.blacklist()))
		"/map":
			_map(sender, argument)
		"/say":
			_say(sender, argument)
		_:
			_notice(sender, "Commands: /kick, /ban <peer_id|nickname|IP>, /unban <IP>, /blacklist, /map, /say")


func _kick(sender: int, argument: String) -> void:
	if not Net.remove_peer(_target(argument), "admin_kick"):
		_notice(sender, "Unknown peer or protected server.")
		return
	_notice(sender, "Peer disconnected.")


func _target(argument: String) -> int:
	var target: int = argument.to_int() if argument.is_valid_int() else 0
	if target == 0:
		for id: int in Net.nicknames:
			if Net.nicknames[id].to_lower() == argument.to_lower():
				target = id
	return target


func _ban(sender: int, argument: String) -> void:
	var target: int = _target(argument)
	var address: String = Net.peer_ip(target) if target > Net.SERVER_ID else argument
	_notice(sender, "IP banned for this session." if Net.ban_ip(address) else "Unknown peer or invalid IP.")


func _map(sender: int, argument: String) -> void:
	var data: MapData = loader.find_map(argument)
	if data == null or not data.is_valid():
		_notice(sender, "Unknown map.")
		return
	loader.change_map.call_deferred(argument)
	_notice(sender, "Changing map: " + argument)


func _say(sender: int, argument: String) -> void:
	var text: String = ChatPolicy.sanitize(argument, config.max_length)
	if text.is_empty():
		_notice(sender, "Usage: /say <text>")
		return
	for recipient: int in recipients(sender, false):
		_deliver(recipient, 0, "SERVER", text, false)


func _notice(recipient: int, text: String) -> void:
	if recipient == multiplayer.get_unique_id():
		notice_received.emit(text)
	else:
		notice.rpc_id(recipient, text)


@rpc("authority", "call_remote", "reliable", 0)
func notice(text: String) -> void:
	if not multiplayer.is_server():
		Net.note_packet(Net.SERVER_ID)
		notice_received.emit(text)


func _forget(peer: int) -> void:
	policy.forget(peer)
	admin.forget(peer)


func reset() -> void:
	policy.clear()
	admin.clear()
