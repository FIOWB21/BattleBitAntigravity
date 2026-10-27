# Чистая проверка данных. Не изменяет комплект и не применяет его к игроку.
class_name LoadoutValidator
extends RefCounted


static func validate(class_data: ClassData, loadout: Loadout) -> Array[String]:
	var errors: Array[String] = []
	if class_data == null:
		errors.append("Class data is required.")
	if loadout == null:
		errors.append("Loadout is required.")
	if not errors.is_empty():
		return errors
	_validate_weapon(loadout.primary, class_data.allowed_primary_categories, "primary", errors)
	_validate_weapon(loadout.secondary, class_data.allowed_secondary_categories, "secondary", errors)
	var seen_ids: Array[StringName] = []
	_validate_gadget(class_data, loadout.gadget_1, Loadout.Slot.GADGET_1, seen_ids, errors)
	_validate_gadget(class_data, loadout.gadget_2, Loadout.Slot.GADGET_2, seen_ids, errors)
	return errors


static func _validate_weapon(weapon: WeaponData, allowed: Array[WeaponData.Category],
		slot_name: String, errors: Array[String]) -> void:
	# null сохраняет существующий контракт Loadout: пустые слоты разрешены.
	if weapon != null and not allowed.has(weapon.category):
		errors.append("Weapon category %d is forbidden in %s." % [weapon.category, slot_name])


static func _validate_gadget(class_data: ClassData, gadget: EquipmentData, slot: Loadout.Slot,
		seen_ids: Array[StringName], errors: Array[String]) -> void:
	if gadget == null:
		return
	if gadget.id == &"":
		errors.append("Gadget in slot %d must have an id." % slot)
		return
	if seen_ids.has(gadget.id):
		errors.append("Duplicate gadget '%s'." % gadget.id)
	else:
		seen_ids.append(gadget.id)
	var permission: GadgetSlotData = _find_slot(class_data, slot)
	if permission == null:
		errors.append("Gadget slot %d is unavailable." % slot)
	elif not permission.allowed_ids.has(gadget.id):
		errors.append("Gadget '%s' is forbidden in slot %d." % [gadget.id, slot])


static func _find_slot(class_data: ClassData, slot: Loadout.Slot) -> GadgetSlotData:
	for permission: GadgetSlotData in class_data.gadget_slots:
		if permission != null and permission.slot == slot:
			return permission
	return null
