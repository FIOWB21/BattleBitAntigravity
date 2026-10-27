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


func _init() -> void:
	reset_debug()
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	detect_runtime_flags(args, OS.has_feature(DEDICATED_FEATURE))


func reset_debug() -> void:
	debug = {
		"ping_ms": 0,
		"loss_percent": 0.0,
		"loss_pct": 0.0,
		"loss": 0.0,
		"god": false,
		"noclip": false,
		"player_position": Vector3.ZERO,
		"max_fps": 0,
	}


func detect_runtime_flags(cmdline_args: PackedStringArray, has_dedicated_feature: bool) -> void:
	var has_server_arg: bool = cmdline_args.has(SERVER_ARG)
	is_dedicated = has_dedicated_feature or has_server_arg
	is_server = is_dedicated


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
