# Чистый резолв: (база + сумма ADD) * произведение MUL, в порядке слотов.
class_name WeaponStats
extends RefCounted

const STATS: Array[StringName] = [
	&"rpm", &"burst_count", &"damage_near", &"damage_far", &"range_near", &"range_far",
	&"headshot_mult", &"limb_mult", &"pellets", &"penetration", &"hitscan_range",
	&"mag_size", &"reserve_mags", &"reload_time", &"reload_empty_time", &"draw_time",
	&"ads_time", &"ads_fov_mult", &"ads_move_speed_mult", &"move_speed_mult",
	&"spread_hip_deg", &"spread_ads_deg", &"recoil_pause", &"recoil_recovery_deg_per_second",
	&"spread_per_shot_deg", &"spread_max_bloom_deg", &"spread_recovery_deg_per_second",
	&"spread_move_deg_per_mps", &"spread_crouch_mult", &"spread_prone_mult",
	&"spread_ads_extra_mult", &"spread_max_deg",
]
const POSITIVE: Array[StringName] = [&"rpm", &"burst_count", &"pellets", &"mag_size", &"hitscan_range"]
const INTEGER_MAX: float = 2147483647.0


# Некорректный комплект отклоняется целиком, без ошибок в консоли и частичного результата.
static func resolve(weapon: WeaponData, attachments: Array[AttachmentData]) -> WeaponData:
	if weapon == null:
		return null
	var slots: Dictionary[int, AttachmentData] = {}
	for attachment: AttachmentData in attachments:
		if attachment == null or attachment.slot < 0 or attachment.slot >= AttachmentData.Slot.size():
			return null
		if slots.has(attachment.slot):
			return null
		slots[attachment.slot] = attachment
	var adds: Dictionary[StringName, float] = {}
	var multipliers: Dictionary[StringName, float] = {}
	for slot: int in range(AttachmentData.Slot.size()):
		if slots.has(slot) and not _accumulate(slots[slot], adds, multipliers):
			return null
	var result: WeaponData = weapon.duplicate() as WeaponData
	for stat: StringName in adds:
		var value: float = (float(weapon.get(stat)) + adds[stat]) * multipliers[stat]
		var integer: bool = typeof(weapon.get(stat)) == TYPE_INT
		if integer:
			value = roundf(value)
		if not is_finite(value) or value < 0.0 or (stat in POSITIVE and value <= 0.0):
			return null
		if integer and value > INTEGER_MAX:
			return null
		result.set(stat, int(value) if integer else value)
	return result


static func _accumulate(attachment: AttachmentData, adds: Dictionary[StringName, float],
		multipliers: Dictionary[StringName, float]) -> bool:
	for modifier: AttachmentModifier in attachment.modifiers:
		if modifier == null or not modifier.stat in STATS or not is_finite(modifier.value):
			return false
		if modifier.op != AttachmentModifier.Operation.ADD and modifier.op != AttachmentModifier.Operation.MUL:
			return false
		var stat: StringName = modifier.stat
		if not adds.has(stat):
			adds[stat] = 0.0
			multipliers[stat] = 1.0
		if modifier.op == AttachmentModifier.Operation.ADD:
			adds[stat] += modifier.value
		else:
			multipliers[stat] *= modifier.value
	return true
