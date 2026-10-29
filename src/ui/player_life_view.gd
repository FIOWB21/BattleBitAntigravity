# Представление жизненного цикла: таймер, прогресс удержания и выбор начального спавна.
class_name PlayerLifeView
extends CanvasLayer

var status_label: Label
var spawn_panel: PanelContainer
var spawn_button: Button
var beacon_button: Button
var progress_bar: ProgressBar
var _title: Label
var _hint: Label
var _life: PlayerLife


func setup(life: PlayerLife) -> void:
	_life = life
	layer = 15
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	status_label.position = Vector2(-220, 80)
	status_label.size = Vector2(440, 50)
	root.add_child(status_label)
	progress_bar = ProgressBar.new()
	progress_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	progress_bar.position = Vector2(-150, -120)
	progress_bar.size = Vector2(300, 24)
	progress_bar.max_value = 1.0
	root.add_child(progress_bar)
	_build_spawn_panel(root)
	life.state_changed.connect(_on_state_changed)
	life.bleedout_changed.connect(_on_bleedout_changed)
	life.interaction.progress_changed.connect(_on_progress_changed)
	_on_state_changed(life.state)
	_on_progress_changed(0.0)


func _build_spawn_panel(root: Control) -> void:
	spawn_panel = PanelContainer.new()
	spawn_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	spawn_panel.position = Vector2(-220, -85)
	spawn_panel.custom_minimum_size = Vector2(440, 170)
	root.add_child(spawn_panel)
	var column: VBoxContainer = VBoxContainer.new()
	spawn_panel.add_child(column)
	var title: Label = Label.new()
	_title = title
	title.text = "SPAWN SELECT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var hint: Label = Label.new()
	_hint = hint
	hint.text = "Choose deployment location"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	spawn_button = Button.new()
	spawn_button.text = "Initial spawn"
	spawn_button.custom_minimum_size.y = 60
	spawn_button.pressed.connect(_life.select_initial_spawn)
	column.add_child(spawn_button)
	beacon_button = Button.new()
	beacon_button.text = "Squad beacon"
	beacon_button.custom_minimum_size.y = 60
	beacon_button.pressed.connect(_on_beacon_pressed)
	column.add_child(beacon_button)


func _on_beacon_pressed() -> void:
	if not _life.select_beacon_spawn():
		beacon_button.text = "No safe squad beacon — try again"


func _on_state_changed(state: PlayerLife.State) -> void:
	spawn_panel.visible = state == PlayerLife.State.SPAWN_SELECT
	status_label.visible = state == PlayerLife.State.DOWNED
	if spawn_panel.visible:
		spawn_button.visible = not _life.network_respawn_managed
		beacon_button.visible = not _life.network_respawn_managed
		if _life.network_respawn_managed:
			_title.text = "RESPAWNING"
			_hint.text = "Server deployment after %.1f s" % _life.rules.respawn_delay
		else:
			beacon_button.text = "Squad beacon"
			spawn_button.grab_focus()


func _on_bleedout_changed(seconds: float) -> void:
	status_label.text = "DOWNED  |  Bleedout: %d s  |  Wait for a medic" % ceili(seconds)


func _on_progress_changed(fraction: float) -> void:
	progress_bar.visible = fraction > 0.0
	progress_bar.value = fraction
