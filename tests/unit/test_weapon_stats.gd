extends GutTest


func _modifier(stat: StringName, op: AttachmentModifier.Operation, value: float) -> AttachmentModifier:
	var modifier: AttachmentModifier = AttachmentModifier.new()
	modifier.stat = stat
	modifier.op = op
	modifier.value = value
	return modifier


func _attachment(slot: AttachmentData.Slot, modifiers: Array[AttachmentModifier]) -> AttachmentData:
	var attachment: AttachmentData = AttachmentData.new()
	attachment.slot = slot
	attachment.modifiers = modifiers
	return attachment


func test_empty_resolve_copies_values_without_mutating_source() -> void:
	var base: WeaponData = WeaponData.new()
	var result: WeaponData = WeaponStats.resolve(base, [])
	assert_ne(result, base)
	assert_eq(result.spread_hip_deg, base.spread_hip_deg)
	result.spread_hip_deg = 99.0
	assert_eq(base.spread_hip_deg, 2.0)
	assert_null(WeaponStats.resolve(null, []))


func test_additions_precede_multiplications_regardless_of_list_order() -> void:
	var base: WeaponData = WeaponData.new()
	var add: AttachmentModifier = _modifier(&"spread_hip_deg", AttachmentModifier.Operation.ADD, 3.0)
	var mul: AttachmentModifier = _modifier(&"spread_hip_deg", AttachmentModifier.Operation.MUL, 2.0)
	var first: AttachmentData = _attachment(AttachmentData.Slot.SIGHT, [mul, add])
	var second: AttachmentData = _attachment(AttachmentData.Slot.GRIP, [
		_modifier(&"spread_hip_deg", AttachmentModifier.Operation.ADD, 1.0),
		_modifier(&"spread_hip_deg", AttachmentModifier.Operation.MUL, 0.5)])
	assert_eq(WeaponStats.resolve(base, [first, second]).spread_hip_deg, 6.0)
	assert_eq(WeaponStats.resolve(base, [second, first]).spread_hip_deg, 6.0)
	first.modifiers = [add, mul]
	assert_eq(WeaponStats.resolve(base, [first, second]).spread_hip_deg, 6.0)
	assert_eq(base.spread_hip_deg, 2.0)


func test_exactly_one_attachment_per_slot_and_null_entries_are_rejected() -> void:
	var base: WeaponData = WeaponData.new()
	for slot: int in range(AttachmentData.Slot.size()):
		var first: AttachmentData = _attachment(slot as AttachmentData.Slot, [])
		var second: AttachmentData = _attachment(slot as AttachmentData.Slot, [])
		assert_null(WeaponStats.resolve(base, [first, second]))
		assert_not_null(WeaponStats.resolve(base, [first]))
	assert_null(WeaponStats.resolve(base, [null]))


func test_all_five_profiles_compose_in_canonical_order() -> void:
	var base: WeaponData = WeaponData.new()
	var attachments: Array[AttachmentData] = []
	for attachment: AttachmentData in AttachmentCommand.PROFILES.values():
		attachments.append(attachment)
	var result: WeaponData = WeaponStats.resolve(base, attachments)
	assert_almost_eq(result.spread_hip_deg, 2.0 * 0.65 * 0.9 * 0.8, 0.000001)
	assert_almost_eq(result.spread_ads_deg, 0.3 * 0.7 * 0.8, 0.000001)
	assert_almost_eq(result.spread_per_shot_deg, 0.35 * 0.7, 0.000001)
	assert_eq(result.mag_size, 40)
	assert_almost_eq(result.reload_time, 2.5, 0.000001)
	for rotation: int in range(attachments.size()):
		attachments.push_back(attachments.pop_front())
		var rotated: WeaponData = WeaponStats.resolve(base, attachments)
		for stat: StringName in WeaponStats.STATS:
			assert_eq(rotated.get(stat), result.get(stat))


func test_unknown_non_numeric_and_null_modifiers_reject_entire_set() -> void:
	var base: WeaponData = WeaponData.new()
	for stat: StringName in [&"missing_stat", &"id", &"category", &"viewmodel_scene", &"recoil_pattern"]:
		var attachment: AttachmentData = _attachment(AttachmentData.Slot.SIGHT, [
			_modifier(stat, AttachmentModifier.Operation.ADD, 1.0)])
		assert_null(WeaponStats.resolve(base, [attachment]))
	var null_modifier: AttachmentData = _attachment(AttachmentData.Slot.SIGHT, [null])
	assert_null(WeaponStats.resolve(base, [null_modifier]))
	assert_eq(base.mag_size, 30)


func test_non_finite_negative_and_zero_required_values_are_rejected() -> void:
	var base: WeaponData = WeaponData.new()
	for value: float in [NAN, INF, -INF, -3.0]:
		var attachment: AttachmentData = _attachment(AttachmentData.Slot.GRIP, [
			_modifier(&"spread_hip_deg", AttachmentModifier.Operation.ADD, value)])
		assert_null(WeaponStats.resolve(base, [attachment]))
	for stat: StringName in WeaponStats.POSITIVE:
		var attachment: AttachmentData = _attachment(AttachmentData.Slot.GRIP, [
			_modifier(stat, AttachmentModifier.Operation.MUL, 0.0)])
		assert_null(WeaponStats.resolve(base, [attachment]))


func test_integer_stats_round_once_after_all_operations_and_reject_overflow() -> void:
	var base: WeaponData = WeaponData.new()
	var attachment: AttachmentData = _attachment(AttachmentData.Slot.MAGAZINE, [
		_modifier(&"mag_size", AttachmentModifier.Operation.MUL, 1.5),
		_modifier(&"mag_size", AttachmentModifier.Operation.ADD, 1.0)])
	assert_eq(WeaponStats.resolve(base, [attachment]).mag_size, 47)
	attachment.modifiers[0].value = 1.0e30
	assert_null(WeaponStats.resolve(base, [attachment]))


func test_invalid_slot_and_operation_and_arithmetic_overflow_are_rejected() -> void:
	var base: WeaponData = WeaponData.new()
	var modifier: AttachmentModifier = _modifier(&"spread_hip_deg", AttachmentModifier.Operation.MUL, 2.0)
	var attachment: AttachmentData = _attachment(AttachmentData.Slot.SIGHT, [modifier])
	attachment.slot = 99 as AttachmentData.Slot
	assert_null(WeaponStats.resolve(base, [attachment]))
	attachment.slot = AttachmentData.Slot.SIGHT
	modifier.op = 99 as AttachmentModifier.Operation
	assert_null(WeaponStats.resolve(base, [attachment]))
	modifier.op = AttachmentModifier.Operation.MUL
	modifier.value = 1.0e300
	attachment.modifiers = [modifier, modifier]
	assert_null(WeaponStats.resolve(base, [attachment]))


func test_profiles_have_unique_ids_slots_models_and_expected_mounts() -> void:
	var ids: Array[StringName] = []
	var slots: Array[int] = []
	for attachment: AttachmentData in AttachmentCommand.PROFILES.values():
		assert_false(ids.has(attachment.id))
		assert_false(slots.has(attachment.slot))
		ids.append(attachment.id)
		slots.append(attachment.slot)
		assert_not_null(attachment.model_scene)
		assert_true(attachment.mount_name() in [&"Muzzle", &"Sight", &"Grip"])
	assert_eq(ids.size(), 5)
