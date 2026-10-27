# Manual networking launcher with cooperative shutdown for all three processes.
extends SceneTree

var _stop_path: String
var _stop_timer: Timer
var _net: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_net = root.get_node("Net")
	root.add_child(load("res://src/ui/main_menu.tscn").instantiate())
	_stop_path = OS.get_environment("NET_TEST_STOP_FILE")
	if _stop_path.is_empty():
		return
	_stop_timer = Timer.new()
	_stop_timer.wait_time = 0.1
	_stop_timer.timeout.connect(_check_shutdown)
	root.add_child(_stop_timer)
	_stop_timer.start()


func _check_shutdown() -> void:
	if FileAccess.file_exists(_stop_path):
		_stop_timer.stop()
		_net.disconnect_all()
		print("NET SESSION CLOSED")
		quit(0)
