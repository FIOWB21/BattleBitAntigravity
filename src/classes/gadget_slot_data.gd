# Разрешения одного слота существующего Loadout; пустой список запрещает предметы.
class_name GadgetSlotData
extends Resource

@export var slot: Loadout.Slot = Loadout.Slot.GADGET_1
@export var allowed_ids: Array[StringName] = []
