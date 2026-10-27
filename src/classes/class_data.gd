# Данные класса; перки являются идентификаторами, а не исполняемыми способностями.
class_name ClassData
extends Resource

@export var id: StringName
@export var display_name: String
@export var max_health: float = 100.0
@export var move_speed_mult: float = 1.0
@export var allowed_primary_categories: Array[WeaponData.Category] = []
@export var allowed_secondary_categories: Array[WeaponData.Category] = []
@export var gadget_slots: Array[GadgetSlotData] = []
@export var passive_perks: Array[StringName] = []
