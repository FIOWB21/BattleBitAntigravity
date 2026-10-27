# Счётчик отдельного заряда и перезарядки подствольника, обновляется сигналами.
class_name LauncherStockView
extends CanvasLayer

var label: Label
var _gadgets: Dictionary[int, Gadget] = {}
var _active: Gadget


func setup(player: Player) -> void:
	layer = 11
	label = Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	label.position = Vector2(-260, -130)
	label.size = Vector2(240, 30)
	add_child(label)
	for slot: int in [Loadout.Slot.GADGET_1, Loadout.Slot.GADGET_2]:
		var gadget: Gadget = player.equipment.gadgets.gadget_at(slot)
		if gadget == null or not gadget.data is LauncherGadgetData:
			continue
		_gadgets[slot] = gadget
		gadget.charges_changed.connect(_on_amount_changed)
		gadget.reload_started.connect(_on_amount_changed)
		gadget.reload_finished.connect(_refresh)
	player.inventory.active_slot_changed.connect(_on_slot_changed)
	_on_slot_changed(player.inventory.active_slot, null)


func _on_slot_changed(slot: int, _weapon: Weapon) -> void:
	_active = _gadgets.get(slot) as Gadget
	_refresh()


func _on_amount_changed(_value: int) -> void:
	_refresh()


func _refresh() -> void:
	visible = _active != null
	if visible:
		label.text = "UNDERBARREL  RELOADING" if _active.reload_end_tick >= 0 \
			else "UNDERBARREL  %d / %d  |  R: reload" % [_active.charges, _active.data.max_charges]
