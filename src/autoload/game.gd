# Глобальное состояние приложения и флаги роли (сервер / клиент).
extends Node

enum State {
	MENU,
	IN_GAME,
}

const SERVER_ARG: String = "--server"
const DEDICATED_FEATURE: String = "dedicated_server"

var state: State = State.MENU
var is_server: bool = false
var is_dedicated: bool = false
var debug: Dictionary = {}
var server_port: int = NetworkConfig.DEFAULT_PORT
var max_clients: int = NetworkConfig.DEFAULT_MAX_CLIENTS
var map_id: String = "testbed"
var server_password: String = ""
var admin_password: String = ""
var argument_errors: Array[String] = []


func _init() -> void:
	reset_debug()
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	detect_runtime_flags(args, OS.has_feature(DEDICATED_FEATURE))
	if is_dedicated:
		argument_errors = parse_server_arguments(OS.get_cmdline_user_args())
	else:
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--admin-password="):
				admin_password = arg.trim_prefix("--admin-password=")


func reset_debug() -> void:
	debug = {
		"ping_ms": 0,
		"loss_percent": 0.0,
		"loss_pct": 0.0,
		"loss": 0.0,
		"god": false,
		"noclip": false,
		"player_position": Vector3.ZERO,
		"reconciliations": 0,
		"prediction_error": 0.0,
		"prediction_teleports": 0,
		"max_fps": 0,
	}


func detect_runtime_flags(cmdline_args: PackedStringArray, has_dedicated_feature: bool) -> void:
	var has_server_arg: bool = cmdline_args.has(SERVER_ARG)
	is_dedicated = has_dedicated_feature or has_server_arg
	is_server = is_dedicated


func parse_server_arguments(args: PackedStringArray) -> Array[String]:
	server_port = NetworkConfig.DEFAULT_PORT
	max_clients = NetworkConfig.DEFAULT_MAX_CLIENTS
	map_id = "testbed"
	server_password = ""
	admin_password = ""
	var errors: Array[String] = []
	var seen: Dictionary[String, bool] = {}
	for arg: String in args:
		var key: String = arg.get_slice("=", 0)
		if seen.has(key):
			errors.append("duplicate_argument: " + key)
			continue
		seen[key] = true
		if key == SERVER_ARG and arg == SERVER_ARG:
			continue
		var value: String = arg.substr(key.length() + 1)
		if not arg.contains("=") or not _apply_server_option(key, value):
			errors.append("invalid_argument: " + key)
	return errors


func _apply_server_option(key: String, value: String) -> bool:
	match key:
		"--port":
			if not value.is_valid_int() or not NetworkConfig.valid_port(value.to_int()):
				return false
			server_port = value.to_int()
		"--max":
			if not value.is_valid_int() or not NetworkConfig.valid_max_clients(value.to_int()):
				return false
			max_clients = value.to_int()
		"--map":
			var pattern: RegEx = RegEx.create_from_string("^[a-z0-9_]+$")
			var matched: RegExMatch = pattern.search(value)
			if matched == null or matched.get_string() != value:
				return false
			map_id = value
		"--password":
			server_password = value
		"--admin-password":
			admin_password = value
		_:
			return false
	return true


func set_state(new_state: State) -> void:
	state = new_state


func is_in_menu() -> bool:
	return state == State.MENU


func is_in_game() -> bool:
	return state == State.IN_GAME


# Учитывает MultiplayerAPI ветки узла; флаги запуска не дают клиенту полномочий.
func is_server_or_offline(api: MultiplayerAPI = null) -> bool:
	if not is_inside_tree():
		return false
	var active_api: MultiplayerAPI = multiplayer if api == null else api
	return active_api.is_server()
