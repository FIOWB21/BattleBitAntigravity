# Отладочный оверлей (F3) и визуальная панель консоли (`).
class_name DebugOverlay
extends CanvasLayer

signal overlay_toggled(visible_state: bool)
signal console_toggled(visible_state: bool)
signal command_executed(command_line: String, output: String)

const TOGGLE_OVERLAY_KEY: Key = KEY_F3
const TOGGLE_CONSOLE_KEY: Key = KEY_QUOTELEFT
const BYTES_PER_MIB: float = 1048576.0
const MS_PER_SECOND: float = 1000.0
const STATS_UPDATE_INTERVAL_SEC: float = 0.1

var console: DebugConsole = null
var commands: Dictionary = {}
var overlay_visible: bool = false
var console_visible: bool = false
var _stats_timer: float = 0.0

@onready var _stats_panel: PanelContainer = $StatsPanel
@onready var _stats_label: Label = $StatsPanel/MarginContainer/StatsLabel
@onready var _console_panel: PanelContainer = $ConsolePanel
@onready var _console_output: RichTextLabel = $ConsolePanel/MarginContainer/VBoxContainer/OutputLabel
@onready var _console_input: LineEdit = $ConsolePanel/MarginContainer/VBoxContainer/InputLine


func _init() -> void:
	console = DebugConsole.new()
	commands = console.commands
	console.command_executed.connect(_on_console_command_executed)


func _ready() -> void:
	if _console_input != null:
		_console_input.text_submitted.connect(_on_input_submitted)
	_apply_visibility()
	update_stats_display()


func _process(delta: float) -> void:
	if not overlay_visible:
		return
	_stats_timer += delta
	if _stats_timer >= STATS_UPDATE_INTERVAL_SEC:
		_stats_timer = 0.0
		update_stats_display()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if _matches_key(key_event, TOGGLE_OVERLAY_KEY):
		toggle_overlay()
		_mark_input_handled()
	elif _matches_key(key_event, TOGGLE_CONSOLE_KEY):
		toggle_console()
		_mark_input_handled()


func toggle_overlay() -> void:
	set_overlay_visible(not overlay_visible)


func set_overlay_visible(new_visible: bool) -> void:
	overlay_visible = new_visible
	_apply_visibility()
	if overlay_visible:
		update_stats_display()
	overlay_toggled.emit(overlay_visible)


func is_overlay_visible() -> bool:
	return overlay_visible


func toggle_console() -> void:
	set_console_visible(not console_visible)


func set_console_visible(new_visible: bool) -> void:
	console_visible = new_visible
	_apply_visibility()
	if console_visible and _console_input != null and is_inside_tree():
		_console_input.grab_focus()
	console_toggled.emit(console_visible)


func is_console_visible() -> bool:
	return console_visible


func register_command(cmd_name: String, callback: Callable) -> void:
	console.register_command(cmd_name, callback)


func parse_command(raw_line: String) -> Dictionary:
	return console.parse_command(raw_line)


func execute_command(raw_line: String) -> String:
	return console.execute_command(raw_line)


func update_stats_display() -> void:
	if _stats_label != null:
		_stats_label.text = format_stats_text()


func format_stats_text() -> String:
	var fps: int = int(Engine.get_frames_per_second())
	var frame_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * MS_PER_SECOND
	var mem_mib: float = float(OS.get_static_memory_usage()) / BYTES_PER_MIB
	var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var pos: Vector3 = Game.debug.get("player_position", Vector3.ZERO)
	var ping_ms: int = int(Game.debug.get("ping_ms", 0))
	return (
		"FPS: %d\nFrame: %.2f ms\nMemory: %.2f MiB\nNodes: %d\nPos: (%.1f, %.1f, %.1f)\nPing: %d ms\nTick: %d / Server: %.1f\nLead: %.1f ticks"
		% [fps, frame_ms, mem_mib, node_count, pos.x, pos.y, pos.z, ping_ms,
			Net.tick, Net.clock.estimated_server_tick(Time.get_ticks_usec()), Net.clock.lead_ticks()]
	)


func _apply_visibility() -> void:
	var stats_node: Control = _stats_panel if _stats_panel != null else get_node_or_null("StatsPanel") as Control
	if stats_node != null:
		stats_node.visible = overlay_visible
	var console_node: Control = _console_panel if _console_panel != null else get_node_or_null("ConsolePanel") as Control
	if console_node != null:
		console_node.visible = console_visible
	visible = overlay_visible or console_visible


func _on_input_submitted(text: String) -> void:
	if _console_input != null:
		_console_input.clear()
	execute_command(text)


func _on_console_command_executed(raw_line: String, output: String) -> void:
	var out_node: RichTextLabel = (
		_console_output
		if _console_output != null
		else get_node_or_null("ConsolePanel/MarginContainer/VBoxContainer/OutputLabel") as RichTextLabel
	)
	if out_node != null and not output.is_empty():
		out_node.append_text("> %s\n%s\n" % [raw_line.strip_edges(), output])
	command_executed.emit(raw_line, output)


func _matches_key(event: InputEventKey, target_key: Key) -> bool:
	return event.keycode == target_key or event.physical_keycode == target_key


func _mark_input_handled() -> void:
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.set_input_as_handled()
