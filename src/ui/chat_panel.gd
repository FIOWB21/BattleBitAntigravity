# Event-driven plain-text presentation; no BBCode parser and no frame polling.
class_name ChatPanel
extends CanvasLayer

const PANEL_WIDTH: float = 580.0
const ROW_HEIGHT: float = 22.0
const MARGIN: float = 16.0
const INPUT_HEIGHT: float = 32.0
const OPEN_CHAT_KEY: Key = KEY_ENTER

var chat: NetworkChat
var editing: bool = false
var field: LineEdit
var channel: OptionButton
var _rows: Array[Label] = []
var _editor: HBoxContainer
var _scroll: ScrollContainer
var _actor: Player
var _recapture: bool = false


func _ready() -> void:
	layer = 20
	_build()
	chat.message_received.connect(_message)
	chat.notice_received.connect(_notice)
	Net.disconnected.connect(_reset)
	chat.loader.map_loaded.connect(_map_loaded)


func _build() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.position = Vector2(MARGIN, MARGIN * 5.0)
	box.size.x = PANEL_WIDTH
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_build_history(box)
	_editor = HBoxContainer.new()
	box.add_child(_editor)
	channel = OptionButton.new()
	channel.add_item("All")
	channel.add_item("Team")
	_editor.add_child(channel)
	field = LineEdit.new()
	field.custom_minimum_size = Vector2(PANEL_WIDTH - 90.0, INPUT_HEIGHT)
	field.max_length = chat.config.max_request_length
	field.placeholder_text = "Message or /admin <password>"
	field.text_submitted.connect(_submit)
	field.text_changed.connect(_text_changed)
	_editor.add_child(field)
	_editor.hide()


func _build_history(box: VBoxContainer) -> void:
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(PANEL_WIDTH, ROW_HEIGHT * chat.config.history_count)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_scroll.get_v_scroll_bar().changed.connect(_scroll_to_bottom)
	var history: VBoxContainer = VBoxContainer.new()
	history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history.add_theme_constant_override("separation", 0)
	_scroll.add_child(history)
	for index: int in range(chat.config.history_count):
		var label: Label = Label.new()
		label.custom_minimum_size.y = ROW_HEIGHT
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_outline_size", 3)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		history.add_child(label)
		_rows.append(label)


func _input(event: InputEvent) -> void:
	if editing and event.is_action_pressed(InputActions.PAUSE_MENU):
		close()
		get_viewport().set_input_as_handled()
	elif not editing and _opens_chat(event):
		open()
		if editing:
			get_viewport().set_input_as_handled()


func _opens_chat(event: InputEvent) -> bool:
	if event.is_echo():
		return false
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == OPEN_CHAT_KEY:
		return true
	return event.is_action_pressed(InputActions.CHAT) \
		and not event.is_action_pressed(InputActions.SWITCH_WEAPON_LAST)


func open() -> void:
	if editing or not Net.is_connected or chat.loader.current_map == null:
		return
	for actor: Player in chat.loader.players.actors.values():
		if actor.is_local_player:
			_actor = actor
	if not is_instance_valid(_actor):
		return
	editing = true
	_recapture = _actor.is_mouse_captured()
	_actor.input_reader.set_blocked(true)
	_actor.release_mouse()
	_editor.show()
	field.grab_focus()


func close() -> void:
	editing = false
	field.clear()
	field.secret = false
	field.release_focus()
	_editor.hide()
	if is_instance_valid(_actor):
		_actor.input_reader.set_blocked(false)
		if _recapture:
			_actor.capture_mouse()
	_actor = null


func _submit(text: String) -> void:
	chat.send(text, channel.selected == 1)
	close()


func _text_changed(text: String) -> void:
	field.secret = text.strip_edges().begins_with("/admin ")


func _message(_sender: int, nickname: String, text: String, team_only: bool) -> void:
	_append("[%s] %s: %s" % ["TEAM" if team_only else "ALL", nickname, text])


func _notice(text: String) -> void:
	_append("[SYSTEM] " + text)


func _append(text: String) -> void:
	for index: int in range(_rows.size() - 1):
		_rows[index].text = _rows[index + 1].text
	_rows[_rows.size() - 1].text = text
	_scroll_to_bottom.call_deferred()


func _scroll_to_bottom() -> void:
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _map_loaded(_map_id: String) -> void:
	close()


func _reset() -> void:
	close()
	for row: Label in _rows:
		row.text = ""


func _exit_tree() -> void:
	if is_instance_valid(_actor):
		_actor.input_reader.set_blocked(false)
