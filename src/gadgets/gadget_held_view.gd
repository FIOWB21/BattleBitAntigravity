# Модели создаются один раз, переключение и запрет действий меняют только видимость.
class_name GadgetHeldView
extends Node3D

var _models: Dictionary[int, Node3D] = {}
var _slot: int = 0


func setup(player: Player) -> void:
	for slot: int in [Loadout.Slot.GADGET_1, Loadout.Slot.GADGET_2]:
		var data: GadgetData = player.inventory.loadout.item_at(slot) as GadgetData
		if data == null or data.model_scene == null:
			continue
		var model: Node3D = data.model_scene.instantiate() as Node3D
		add_child(model)
		_models[slot] = model
	player.inventory.active_slot_changed.connect(_on_slot_changed)
	_on_slot_changed(player.inventory.active_slot, null)


func set_active(active: bool) -> void:
	visible = active


func _on_slot_changed(slot: int, _weapon: Weapon) -> void:
	_slot = slot
	for key: int in _models:
		_models[key].visible = key == _slot
