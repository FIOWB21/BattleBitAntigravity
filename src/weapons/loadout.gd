# Пять фиксированных слотов комплекта. null означает пустой слот.
class_name Loadout
extends Resource

enum Slot { NONE, PRIMARY, SECONDARY, GADGET_1, GADGET_2, GRENADE_MELEE }

const SLOT_COUNT: int = 5

@export var primary: WeaponData
@export var secondary: WeaponData
@export var gadget_1: EquipmentData
@export var gadget_2: EquipmentData
@export var grenade_melee: EquipmentData


func item_at(slot: int) -> Resource:
	match slot:
		Slot.PRIMARY: return primary
		Slot.SECONDARY: return secondary
		Slot.GADGET_1: return gadget_1
		Slot.GADGET_2: return gadget_2
		Slot.GRENADE_MELEE: return grenade_melee
	return null


func draw_time_at(slot: int) -> float:
	var item: Resource = item_at(slot)
	if item is WeaponData:
		return (item as WeaponData).draw_time
	if item is EquipmentData:
		return (item as EquipmentData).draw_time
	return 0.0
