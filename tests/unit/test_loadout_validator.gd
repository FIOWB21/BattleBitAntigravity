extends GutTest

var _class_data: ClassData
var _loadout: Loadout


func before_each() -> void:
	_class_data = ClassData.new()
	_class_data.allowed_primary_categories = [WeaponData.Category.AR]
	_class_data.allowed_secondary_categories = [WeaponData.Category.PISTOL]
	_class_data.gadget_slots = [
		_permission(Loadout.Slot.GADGET_1, [&"medkit", &"defibrillator"]),
		_permission(Loadout.Slot.GADGET_2, [&"medkit", &"defibrillator"]),
	]
	_loadout = Loadout.new()
	_loadout.primary = _weapon(WeaponData.Category.AR)
	_loadout.secondary = _weapon(WeaponData.Category.PISTOL)
	_loadout.gadget_1 = _gadget(&"medkit")
	_loadout.gadget_2 = _gadget(&"defibrillator")


func _weapon(category: WeaponData.Category) -> WeaponData:
	var data: WeaponData = WeaponData.new()
	data.category = category
	return data


func _gadget(id: StringName) -> EquipmentData:
	var data: EquipmentData = EquipmentData.new()
	data.id = id
	return data


func _permission(slot: Loadout.Slot, ids: Array[StringName]) -> GadgetSlotData:
	var data: GadgetSlotData = GadgetSlotData.new()
	data.slot = slot
	data.allowed_ids = ids
	return data


func test_valid_complete_loadout_has_no_errors() -> void:
	assert_eq(LoadoutValidator.validate(_class_data, _loadout), [])


func test_empty_loadout_and_individually_empty_slots_are_valid() -> void:
	assert_eq(LoadoutValidator.validate(_class_data, Loadout.new()), [])
	for property: StringName in [&"primary", &"secondary", &"gadget_1", &"gadget_2"]:
		var partial: Loadout = _loadout.duplicate() as Loadout
		partial.set(property, null)
		assert_eq(LoadoutValidator.validate(_class_data, partial), [], property)


func test_null_arguments_return_errors_without_engine_errors() -> void:
	assert_eq(LoadoutValidator.validate(null, _loadout), ["Class data is required."])
	assert_eq(LoadoutValidator.validate(_class_data, null), ["Loadout is required."])
	assert_eq(LoadoutValidator.validate(null, null),
		["Class data is required.", "Loadout is required."])


func test_wrong_primary_and_secondary_report_both_slot_names() -> void:
	_loadout.primary = _weapon(WeaponData.Category.SNIPER)
	_loadout.secondary = _weapon(WeaponData.Category.AR)
	assert_eq(LoadoutValidator.validate(_class_data, _loadout), [
		"Weapon category 4 is forbidden in primary.",
		"Weapon category 0 is forbidden in secondary.",
	])


func test_empty_category_allowlists_deny_equipped_weapons() -> void:
	_class_data.allowed_primary_categories.clear()
	_class_data.allowed_secondary_categories.clear()
	assert_eq(LoadoutValidator.validate(_class_data, _loadout).size(), 2)
	_loadout.primary = null
	_loadout.secondary = null
	assert_eq(LoadoutValidator.validate(_class_data, _loadout), [])


func test_unknown_category_is_rejected() -> void:
	_loadout.primary.set("category", 999)
	assert_eq(LoadoutValidator.validate(_class_data, _loadout),
		["Weapon category 999 is forbidden in primary."])


func test_duplicate_gadget_reference_is_rejected() -> void:
	_loadout.gadget_2 = _loadout.gadget_1
	assert_eq(LoadoutValidator.validate(_class_data, _loadout), ["Duplicate gadget 'medkit'."])


func test_distinct_resources_with_same_gadget_id_are_duplicates() -> void:
	_loadout.gadget_2 = _gadget(&"medkit")
	assert_ne(_loadout.gadget_1, _loadout.gadget_2)
	assert_eq(LoadoutValidator.validate(_class_data, _loadout), ["Duplicate gadget 'medkit'."])


func test_matching_names_with_distinct_ids_are_not_duplicates() -> void:
	_loadout.gadget_1.display_name = "Equipment"
	_loadout.gadget_2.display_name = "Equipment"
	assert_eq(LoadoutValidator.validate(_class_data, _loadout), [])


func test_empty_gadget_ids_are_rejected_in_both_slots() -> void:
	_loadout.gadget_1.id = &""
	_loadout.gadget_2.id = &""
	assert_eq(LoadoutValidator.validate(_class_data, _loadout), [
		"Gadget in slot 3 must have an id.", "Gadget in slot 4 must have an id.",
	])


func test_permissions_are_checked_for_each_slot() -> void:
	_class_data.gadget_slots[0].allowed_ids = [&"medkit"]
	_class_data.gadget_slots[1].allowed_ids = [&"defibrillator"]
	_loadout.gadget_1 = _gadget(&"defibrillator")
	_loadout.gadget_2 = _gadget(&"medkit")
	assert_eq(LoadoutValidator.validate(_class_data, _loadout), [
		"Gadget 'defibrillator' is forbidden in slot 3.",
		"Gadget 'medkit' is forbidden in slot 4.",
	])


func test_unavailable_and_empty_permission_slots_deny_gadgets() -> void:
	_class_data.gadget_slots[0].allowed_ids.clear()
	_class_data.gadget_slots.remove_at(1)
	assert_eq(LoadoutValidator.validate(_class_data, _loadout), [
		"Gadget 'medkit' is forbidden in slot 3.", "Gadget slot 4 is unavailable.",
	])
	_loadout.gadget_1 = null
	_loadout.gadget_2 = null
	assert_eq(LoadoutValidator.validate(_class_data, _loadout), [])


func test_null_permission_is_safe_and_permissions_are_matched_by_slot() -> void:
	_class_data.gadget_slots.reverse()
	_class_data.gadget_slots.push_front(null)
	assert_eq(LoadoutValidator.validate(_class_data, _loadout), [])
	_class_data.gadget_slots.clear()
	assert_eq(LoadoutValidator.validate(_class_data, _loadout), [
		"Gadget slot 3 is unavailable.", "Gadget slot 4 is unavailable.",
	])


func test_all_errors_are_collected_in_stable_slot_order() -> void:
	_loadout.primary = _weapon(WeaponData.Category.LMG)
	_loadout.secondary = _weapon(WeaponData.Category.SMG)
	_loadout.gadget_1 = _gadget(&"mine")
	_loadout.gadget_2 = _gadget(&"mine")
	assert_eq(LoadoutValidator.validate(_class_data, _loadout), [
		"Weapon category 2 is forbidden in primary.",
		"Weapon category 1 is forbidden in secondary.",
		"Gadget 'mine' is forbidden in slot 3.",
		"Duplicate gadget 'mine'.", "Gadget 'mine' is forbidden in slot 4.",
	])


func test_validation_is_repeatable_and_does_not_mutate_input_resources() -> void:
	_loadout.gadget_2 = _gadget(&"medkit")
	var primary: WeaponData = _loadout.primary
	var gadget: EquipmentData = _loadout.gadget_2
	var permission: GadgetSlotData = _class_data.gadget_slots[0]
	var expected: Array[String] = LoadoutValidator.validate(_class_data, _loadout)
	for iteration: int in range(100):
		assert_eq(LoadoutValidator.validate(_class_data, _loadout), expected)
	assert_eq(_loadout.primary, primary)
	assert_eq(_loadout.primary.category, WeaponData.Category.AR)
	assert_eq(_loadout.gadget_2, gadget)
	assert_eq(gadget.id, &"medkit")
	assert_eq(_class_data.gadget_slots[0], permission)
	assert_eq(permission.allowed_ids, [&"medkit", &"defibrillator"])
	assert_eq(_class_data.allowed_primary_categories, [WeaponData.Category.AR])
	assert_eq(_class_data.allowed_secondary_categories, [WeaponData.Category.PISTOL])


func test_returned_errors_do_not_leak_between_calls() -> void:
	var errors: Array[String] = LoadoutValidator.validate(_class_data, _loadout)
	errors.append("caller-owned")
	assert_eq(LoadoutValidator.validate(_class_data, _loadout), [])


func test_grenade_melee_slot_keeps_existing_independent_contract() -> void:
	_loadout.grenade_melee = _loadout.gadget_1
	assert_eq(LoadoutValidator.validate(_class_data, _loadout), [])
