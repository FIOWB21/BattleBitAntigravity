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


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	detect_runtime_flags(args, OS.has_feature(DEDICATED_FEATURE))


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
