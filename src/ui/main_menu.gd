class_name MainMenu
extends Control

@onready var address: LineEdit = %Address
@onready var port: SpinBox = %Port
@onready var nickname: LineEdit = %Nickname
@onready var password_field: LineEdit = %Password
@onready var host_button: Button = %Host
@onready var join_button: Button = %Join
@onready var disconnect_button: Button = %Disconnect
@onready var status: Label = %Status


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.set_state(Game.State.MENU)
	host_button.pressed.connect(_host)
	join_button.pressed.connect(_join)
	disconnect_button.pressed.connect(Net.disconnect_all)
	Net.connected_to_server.connect(_connected)
	Net.connection_failed.connect(_failed)
	Net.disconnected.connect(_disconnected)
	Net.peer_joined.connect(_peer_changed)
	Net.peer_left.connect(_peer_left)
	if Game.is_dedicated:
		_start_dedicated()
	else:
		_join_from_arguments()


func _start_dedicated() -> void:
	hide()
	if not Game.argument_errors.is_empty():
		printerr("SERVER ARGUMENTS: ", Game.argument_errors)
		get_tree().quit(2)
		return
	Net.password = Game.server_password
	var result: Error = Net.start_server(Game.server_port, Game.max_clients, false)
	if result != OK:
		printerr("SERVER START FAILED: ", error_string(result))
		get_tree().quit(1)
		return
	Log.i("NET SERVER port=%d max=%d map=%s" % [Game.server_port, Game.max_clients, Game.map_id])


func _join_from_arguments() -> void:
	var auto_join: bool = false
	for arg: String in OS.get_cmdline_user_args():
		var value: String = arg.substr(arg.find("=") + 1)
		match arg.get_slice("=", 0):
			"--join":
				address.text = value
				auto_join = true
			"--nickname":
				nickname.text = value
			"--port":
				port.value = value.to_int()
			"--password":
				password_field.text = value
	if auto_join:
		_join()


func _host() -> void:
	_set_credentials()
	var result: Error = Net.start_server(int(port.value), NetworkConfig.DEFAULT_MAX_CLIENTS)
	if result != OK:
		status.text = "Host failed: " + error_string(result)
		return
	_set_busy(true)
	status.text = "Hosting on UDP %d as %s" % [int(port.value), nickname.text]


func _join() -> void:
	_set_credentials()
	var result: Error = Net.join(address.text, int(port.value))
	if result != OK:
		status.text = "Join failed: " + error_string(result)
		return
	_set_busy(true)
	status.text = "Connecting to %s:%d..." % [address.text, int(port.value)]


func _set_credentials() -> void:
	Net.local_nickname = nickname.text
	Net.password = password_field.text


func _set_busy(busy: bool) -> void:
	host_button.disabled = busy
	join_button.disabled = busy
	disconnect_button.disabled = not busy
	address.editable = not busy
	nickname.editable = not busy
	password_field.editable = not busy
	port.editable = not busy


func _connected() -> void:
	status.text = "Connected as " + Net.local_nickname


func _failed() -> void:
	_set_busy(false)
	status.text = "Connection failed: " + Net.last_error


func _disconnected() -> void:
	_set_busy(false)
	status.text = "Disconnected"


func _peer_changed(_id: int, _nickname: String) -> void:
	if multiplayer.is_server():
		status.text = "Hosting: %d accepted peers" % Net.nicknames.size()


func _peer_left(_id: int) -> void:
	_peer_changed(0, "")
