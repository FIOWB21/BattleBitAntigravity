extends GutTest

const DATA_DIR: String = "res://src/weapons/data/"
const SAMPLE_NAMES: Array[String] = [
	"ar", "smg", "lmg", "dmr", "sniper", "shotgun", "pistol", "launcher",
]
const EPSILON: float = 0.00001


func test_damage_at_boundaries_and_outside_range() -> void:
	var data: WeaponData = WeaponData.new()
	assert_almost_eq(data.damage_at(-10.0), 30.0, EPSILON)
	assert_almost_eq(data.damage_at(0.0), 30.0, EPSILON)
	assert_almost_eq(data.damage_at(25.0), 30.0, EPSILON)
	assert_almost_eq(data.damage_at(80.0), 18.0, EPSILON)
	assert_almost_eq(data.damage_at(500.0), 18.0, EPSILON)


func test_damage_falloff_uses_configured_values() -> void:
	var data: WeaponData = WeaponData.new()
	data.damage_near = 40.0
	data.damage_far = 20.0
	data.range_near = 10.0
	data.range_far = 50.0
	assert_almost_eq(data.damage_at(20.0), 35.0, EPSILON)
	assert_almost_eq(data.damage_at(30.0), 30.0, EPSILON)
	assert_almost_eq(data.damage_at(40.0), 25.0, EPSILON)
	data.damage_far = data.damage_near
	assert_almost_eq(data.damage_at(30.0), 40.0, EPSILON)


func test_cooldown_converts_rpm_to_seconds() -> void:
	var data: WeaponData = WeaponData.new()
	assert_almost_eq(data.cooldown(), 60.0 / 700.0, EPSILON)
	data.rpm = 60.0
	assert_almost_eq(data.cooldown(), 1.0, EPSILON)
	data.rpm = 600.0
	assert_almost_eq(data.cooldown(), 0.1, EPSILON)
	data.rpm = 900.0
	assert_almost_eq(data.cooldown(), 1.0 / 15.0, EPSILON)


func test_one_loadable_sample_for_every_category() -> void:
	var ids: Array[StringName] = []
	assert_eq(SAMPLE_NAMES.size(), WeaponData.Category.size())
	for category: int in range(SAMPLE_NAMES.size()):
		var path: String = DATA_DIR + SAMPLE_NAMES[category] + ".tres"
		var data: WeaponData = load(path) as WeaponData
		assert_not_null(data, path)
		if data == null:
			continue
		assert_eq(data.category, category, path)
		assert_ne(data.id, &"", path)
		assert_does_not_have(ids, data.id, "Sample IDs must be unique")
		ids.append(data.id)
		assert_false(data.display_name.is_empty(), path)
		assert_false(data.fire_modes.is_empty(), path)
		for mode: WeaponData.FireMode in data.fire_modes:
			assert_has(WeaponData.FireMode.values(), mode, path)
		assert_gt(data.rpm, 0.0, path)
		assert_gt(data.mag_size, 0, path)
		assert_gt(data.pellets, 0, path)
		assert_gt(data.range_far, data.range_near, path)
		assert_almost_eq(data.damage_at(data.range_near), data.damage_near, EPSILON, path)
		assert_almost_eq(data.damage_at(data.range_far), data.damage_far, EPSILON, path)
		assert_almost_eq(data.cooldown() * data.rpm, 60.0, EPSILON, path)
