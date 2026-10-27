extends GutTest

const DATA_DIR: String = "res://src/classes/data/"
const CLASS_IDS: Array[StringName] = [&"assault", &"medic", &"support", &"engineer", &"recon"]
# Независимая таблица политики для каждого из пяти классов.
const PRIMARY_ALLOWED: Array[Array] = [
	[WeaponData.Category.AR, WeaponData.Category.SMG, WeaponData.Category.SHOTGUN],
	[WeaponData.Category.AR, WeaponData.Category.SMG, WeaponData.Category.SHOTGUN],
	[WeaponData.Category.LMG, WeaponData.Category.SHOTGUN],
	[WeaponData.Category.SMG, WeaponData.Category.SHOTGUN, WeaponData.Category.LAUNCHER],
	[WeaponData.Category.DMR, WeaponData.Category.SNIPER],
]


func _profile(id: StringName) -> ClassData:
	return load(DATA_DIR + String(id) + ".tres") as ClassData


func test_exactly_five_loadable_profiles_with_unique_ids() -> void:
	var files: PackedStringArray = DirAccess.get_files_at(DATA_DIR)
	var ids: Array[StringName] = []
	assert_eq(files.size(), CLASS_IDS.size())
	for id: StringName in CLASS_IDS:
		var data: ClassData = _profile(id)
		assert_not_null(data, String(id))
		if data == null:
			continue
		assert_eq(data.id, id)
		assert_does_not_have(ids, data.id)
		ids.append(data.id)
		assert_false(data.display_name.is_empty())
		assert_true(is_finite(data.max_health))
		assert_gt(data.max_health, 0.0)
		assert_true(is_finite(data.move_speed_mult))
		assert_gt(data.move_speed_mult, 0.0)


func test_each_profile_has_two_distinct_valid_gadget_slots() -> void:
	for id: StringName in CLASS_IDS:
		var data: ClassData = _profile(id)
		assert_eq(data.gadget_slots.size(), 2, String(id))
		var seen: Array[Loadout.Slot] = []
		for slot: GadgetSlotData in data.gadget_slots:
			assert_not_null(slot)
			assert_has([Loadout.Slot.GADGET_1, Loadout.Slot.GADGET_2], slot.slot)
			assert_does_not_have(seen, slot.slot)
			seen.append(slot.slot)
			assert_false(slot.allowed_ids.is_empty())
			var ids: Array[StringName] = []
			for gadget_id: StringName in slot.allowed_ids:
				assert_ne(gadget_id, &"")
				assert_does_not_have(ids, gadget_id)
				ids.append(gadget_id)


func test_all_primary_and_secondary_category_combinations() -> void:
	for index: int in range(CLASS_IDS.size()):
		var data: ClassData = _profile(CLASS_IDS[index])
		for category: WeaponData.Category in WeaponData.Category.values():
			var weapon: WeaponData = WeaponData.new()
			weapon.category = category
			var loadout: Loadout = Loadout.new()
			loadout.primary = weapon
			var primary_allowed: bool = PRIMARY_ALLOWED[index].has(category)
			assert_eq(LoadoutValidator.validate(data, loadout).is_empty(), primary_allowed,
				"%s primary %d" % [data.id, category])
			loadout.primary = null
			loadout.secondary = weapon
			assert_eq(LoadoutValidator.validate(data, loadout).is_empty(),
				category == WeaponData.Category.PISTOL, "%s secondary %d" % [data.id, category])


func test_every_class_accepts_a_full_loadout_and_rejects_unknown_gadget() -> void:
	for id: StringName in CLASS_IDS:
		var data: ClassData = _profile(id)
		var loadout: Loadout = Loadout.new()
		loadout.primary = WeaponData.new()
		loadout.primary.category = data.allowed_primary_categories[0]
		loadout.secondary = WeaponData.new()
		loadout.secondary.category = WeaponData.Category.PISTOL
		loadout.gadget_1 = EquipmentData.new()
		loadout.gadget_1.id = data.gadget_slots[0].allowed_ids[0]
		loadout.gadget_2 = EquipmentData.new()
		var choices: Array[StringName] = data.gadget_slots[1].allowed_ids
		loadout.gadget_2.id = choices[choices.size() - 1]
		assert_eq(LoadoutValidator.validate(data, loadout), [], String(id))
		loadout.gadget_2.id = &"unknown_gadget"
		assert_eq(LoadoutValidator.validate(data, loadout).size(), 1, String(id))


func test_class_roles_are_described_by_data() -> void:
	assert_gt(_profile(&"assault").move_speed_mult, _profile(&"medic").move_speed_mult)
	assert_has(_profile(&"assault").gadget_slots[0].allowed_ids, &"underslung_launcher")
	assert_has(_profile(&"medic").gadget_slots[0].allowed_ids, &"medkit")
	assert_has(_profile(&"medic").gadget_slots[1].allowed_ids, &"defibrillator")
	assert_has(_profile(&"medic").passive_perks, &"revive")
	assert_has(_profile(&"support").gadget_slots[0].allowed_ids, &"ammo_box")
	assert_has(_profile(&"support").passive_perks, &"suppression")
	assert_has(_profile(&"engineer").gadget_slots[0].allowed_ids, &"repair_tool")
	assert_has(_profile(&"engineer").gadget_slots[0].allowed_ids, &"anti_tank_launcher")
	assert_has(_profile(&"engineer").gadget_slots[1].allowed_ids, &"mine")
	assert_has(_profile(&"recon").gadget_slots[1].allowed_ids, &"spawn_beacon")
	assert_has(_profile(&"recon").passive_perks, &"target_spotting")


func test_category_and_perk_lists_have_no_invalid_or_duplicate_entries() -> void:
	for id: StringName in CLASS_IDS:
		var data: ClassData = _profile(id)
		_check_categories(data.allowed_primary_categories)
		_check_categories(data.allowed_secondary_categories)
		var seen: Array[StringName] = []
		for perk: StringName in data.passive_perks:
			assert_ne(perk, &"")
			assert_does_not_have(seen, perk)
			seen.append(perk)


func _check_categories(categories: Array[WeaponData.Category]) -> void:
	assert_false(categories.is_empty())
	var seen: Array[WeaponData.Category] = []
	for category: WeaponData.Category in categories:
		assert_has(WeaponData.Category.values(), category)
		assert_does_not_have(seen, category)
		seen.append(category)


func test_existing_default_loadout_is_valid_for_assault_and_resources_stay_shared() -> void:
	var loadout: Loadout = load("res://src/weapons/data/default_loadout.tres") as Loadout
	var data: ClassData = _profile(&"assault")
	assert_eq(LoadoutValidator.validate(data, loadout), [])
	assert_eq(_profile(&"assault"), data)
	assert_eq(loadout.primary, load("res://src/weapons/data/ar.tres"))
	assert_eq(loadout.secondary, load("res://src/weapons/data/pistol.tres"))
