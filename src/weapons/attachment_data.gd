# Собственный профиль обвеса; модель не участвует в серверном расчёте.
class_name AttachmentData
extends Resource

enum Slot { SIGHT, MUZZLE, BARREL, GRIP, MAGAZINE }

@export var id: StringName
@export var display_name: String
@export var slot: Slot = Slot.SIGHT
@export var modifiers: Array[AttachmentModifier] = []
@export var model_scene: PackedScene


func mount_name() -> StringName:
	match slot:
		Slot.SIGHT: return &"Sight"
		Slot.MUZZLE, Slot.BARREL: return &"Muzzle"
		Slot.GRIP, Slot.MAGAZINE: return &"Grip"
	return &""
