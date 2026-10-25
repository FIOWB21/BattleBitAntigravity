# Глобальный логгер с уровнями и префиксом времени и роли [SERVER]/[CLIENT].
extends Node

enum Level {
	DEBUG,
	INFO,
	WARN,
	ERROR,
}

var min_level: Level = Level.DEBUG
var last_line: String = ""


func d(msg: String) -> void:
	_out(Level.DEBUG, msg)


func i(msg: String) -> void:
	_out(Level.INFO, msg)


func w(msg: String) -> void:
	_out(Level.WARN, msg)


func e(msg: String) -> void:
	_out(Level.ERROR, msg)


func format_message(level: Level, msg: String) -> String:
	var role: String = _get_role_label()
	var level_name: String = str(Level.keys()[level])
	return "[%s][%s][%s] %s" % [Time.get_time_string_from_system(), role, level_name, msg]


func _get_role_label() -> String:
	if Game != null and Game.is_server:
		return "SERVER"
	return "CLIENT"


func _out(level: Level, msg: String) -> void:
	if level < min_level:
		return
	var line: String = format_message(level, msg)
	last_line = line
	if level == Level.ERROR:
		push_error(line)
	else:
		print(line)
