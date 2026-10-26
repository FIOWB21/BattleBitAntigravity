# Генератор сцены базового HUD res://src/ui/hud/hud.tscn.
extends SceneTree

const OUTPUT_PATH: String = "res://src/ui/hud/hud.tscn"
const HUD_SCRIPT_PATH: String = "res://src/ui/hud/hud.gd"

const HUD_LAYER: int = 10
const PANEL_MARGIN: int = 10
const CROSSHAIR_DOT_SIZE: Vector2 = Vector2(4.0, 4.0)
const HEALTH_BAR_MIN_SIZE: Vector2 = Vector2(220.0, 22.0)


func _initialize() -> void:
	var hud: CanvasLayer = _build_hud_scene()
	_set_owner_recursive(hud, hud)
	var packed: PackedScene = PackedScene.new()
	var pack_err: Error = packed.pack(hud)
	hud.free()
	if pack_err != OK:
		printerr("GEN_HUD FAIL pack: ", pack_err)
		quit(1)
		return
	var save_err: Error = ResourceSaver.save(packed, OUTPUT_PATH)
	if save_err != OK:
		printerr("GEN_HUD FAIL save: ", save_err)
		quit(1)
		return
	print("GEN_HUD OK: ", OUTPUT_PATH)
	quit(0)


func _build_hud_scene() -> CanvasLayer:
	var hud_script: GDScript = load(HUD_SCRIPT_PATH) as GDScript
	var hud: CanvasLayer = hud_script.new() as CanvasLayer
	hud.name = "HUD"
	hud.layer = HUD_LAYER

	var root: Control = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	_add_crosshair(root)
	_add_bottom_left_panel(root)
	_add_bottom_right_panel(root)
	return hud


func _add_crosshair(root: Control) -> void:
	var center: CenterContainer = CenterContainer.new()
	center.name = "CrosshairContainer"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var dot: ColorRect = ColorRect.new()
	dot.name = "CrosshairDot"
	dot.custom_minimum_size = CROSSHAIR_DOT_SIZE
	dot.color = Color(1.0, 1.0, 1.0, 0.9)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(dot)


func _add_bottom_left_panel(root: Control) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "BottomLeftPanel"
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 20.0
	panel.offset_top = -120.0
	panel.offset_right = 264.0
	panel.offset_bottom = -20.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var margin: MarginContainer = _create_margin_container()
	panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)
	_add_health_and_stance_widgets(vbox)


func _add_health_and_stance_widgets(vbox: VBoxContainer) -> void:
	var health_bar: ProgressBar = ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.min_value = 0.0
	health_bar.max_value = 100.0
	health_bar.value = 100.0
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = HEALTH_BAR_MIN_SIZE
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(health_bar)

	var health_label: Label = Label.new()
	health_label.name = "HealthLabel"
	health_label.text = "100 / 100"
	vbox.add_child(health_label)

	var stance_label: Label = Label.new()
	stance_label.name = "StanceLabel"
	stance_label.text = "STAND"
	vbox.add_child(stance_label)


func _add_bottom_right_panel(root: Control) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "BottomRightPanel"
	panel.anchor_left = 1.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -180.0
	panel.offset_top = -80.0
	panel.offset_right = -20.0
	panel.offset_bottom = -20.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var margin: MarginContainer = _create_margin_container()
	panel.add_child(margin)

	var ammo_label: Label = Label.new()
	ammo_label.name = "AmmoLabel"
	ammo_label.text = "30 / 120"
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	margin.add_child(ammo_label)


func _create_margin_container() -> MarginContainer:
	var margin: MarginContainer = MarginContainer.new()
	margin.name = "MarginContainer"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", PANEL_MARGIN)
	margin.add_theme_constant_override("margin_top", PANEL_MARGIN)
	margin.add_theme_constant_override("margin_right", PANEL_MARGIN)
	margin.add_theme_constant_override("margin_bottom", PANEL_MARGIN)
	return margin


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		_set_owner_recursive(child, owner_node)
