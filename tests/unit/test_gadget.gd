extends GutTest

const PROFILE: String = "res://src/gadgets/data/base_gadget.tres"

var _uses: Array[int] = []
var _changes: Array[int] = []
var _starts: Array[int] = []
var _finishes: int = 0


func before_each() -> void:
	_uses.clear()
	_changes.clear()
	_starts.clear()
	_finishes = 0


func _gadget(count: int = 2, cooldown: float = 0.5, reload_time: float = 1.5) -> Gadget:
	var profile: GadgetData = load(PROFILE).duplicate() as GadgetData
	profile.max_charges = count
	profile.cooldown = cooldown
	profile.reload_time = reload_time
	var gadget: Gadget = Gadget.new()
	gadget.data = profile
	gadget.ticks_per_second = 60
	gadget.used.connect(func(ctx: GadgetContext) -> void: _uses.append(ctx.tick))
	gadget.charges_changed.connect(func(value: int) -> void: _changes.append(value))
	gadget.reload_started.connect(func(tick: int) -> void: _starts.append(tick))
	gadget.reload_finished.connect(func() -> void: _finishes += 1)
	add_child_autofree(gadget)
	return gadget


func _ctx(tick: int) -> GadgetContext:
	var ctx: GadgetContext = GadgetContext.new()
	ctx.tick = tick
	ctx.source_id = 17
	return ctx


func test_profile_loads_and_fits_existing_equipment_slots() -> void:
	var profile: GadgetData = load(PROFILE) as GadgetData
	assert_true(profile.is_valid())
	assert_eq(profile.id, &"base_gadget")
	var loadout: Loadout = Loadout.new()
	loadout.gadget_1 = profile
	assert_eq(loadout.gadget_1, profile)


func test_initial_charges_and_use_event() -> void:
	var gadget: Gadget = _gadget()
	assert_false(gadget.can_use())
	gadget.simulate(0)
	assert_true(gadget.can_use())
	assert_true(gadget.use(_ctx(0)))
	assert_eq(gadget.charges, 1)
	assert_eq(_uses, [0])
	assert_eq(_changes, [2, 1])


func test_cooldown_rejects_before_boundary_and_accepts_exact_tick() -> void:
	var gadget: Gadget = _gadget()
	assert_true(gadget.use(_ctx(5)))
	assert_eq(gadget.next_use_tick, 35)
	assert_false(gadget.use(_ctx(34)))
	assert_eq(gadget.charges, 1)
	assert_true(gadget.use(_ctx(35)))
	assert_eq(_uses, [5, 35])


func test_exhausted_charges_do_not_regenerate_with_time() -> void:
	var gadget: Gadget = _gadget(1)
	assert_true(gadget.use(_ctx(0)))
	gadget.simulate(10000)
	assert_false(gadget.can_use())
	assert_false(gadget.use(_ctx(10000)))
	assert_eq(gadget.charges, 0)
	assert_eq(_uses, [0])


func test_reload_refills_once_at_exact_deadline() -> void:
	var gadget: Gadget = _gadget()
	assert_true(gadget.use(_ctx(0)))
	assert_true(gadget.reload(1))
	assert_eq(gadget.reload_end_tick, 91)
	gadget.simulate(90)
	assert_eq(gadget.charges, 1)
	assert_eq(_finishes, 0)
	assert_false(gadget.can_use())
	gadget.simulate(91)
	assert_eq(gadget.charges, 2)
	assert_eq(gadget.reload_end_tick, -1)
	assert_eq(_finishes, 1)
	assert_true(gadget.can_use())
	gadget.simulate(91)
	gadget.simulate(1000)
	assert_eq(_finishes, 1)
	assert_eq(_changes, [2, 1, 2])


func test_full_or_repeated_reload_does_not_restart_timer() -> void:
	var gadget: Gadget = _gadget()
	assert_false(gadget.reload(0))
	assert_true(gadget.use(_ctx(1)))
	assert_false(gadget.reload(1))
	assert_true(gadget.reload(2))
	assert_false(gadget.reload(3))
	assert_eq(gadget.reload_end_tick, 92)
	assert_eq(_starts, [92])


func test_use_during_reload_does_not_spend_charge_or_queue_action() -> void:
	var gadget: Gadget = _gadget()
	gadget.use(_ctx(0))
	gadget.reload(1)
	assert_false(gadget.use(_ctx(60)))
	gadget.simulate(91)
	assert_eq(gadget.charges, 2)
	assert_eq(_uses, [0])
	assert_true(gadget.use(_ctx(91)))


func test_reload_does_not_erase_longer_cooldown() -> void:
	var gadget: Gadget = _gadget(2, 2.0, 0.1)
	gadget.use(_ctx(0))
	gadget.reload(1)
	gadget.simulate(7)
	assert_eq(gadget.charges, 2)
	assert_false(gadget.can_use())
	assert_false(gadget.use(_ctx(119)))
	assert_true(gadget.use(_ctx(120)))


func test_duplicate_and_old_commands_do_not_change_state() -> void:
	var gadget: Gadget = _gadget(3, 0.0)
	assert_true(gadget.use(_ctx(10)))
	assert_false(gadget.use(_ctx(10)))
	assert_false(gadget.use(_ctx(9)))
	assert_false(gadget.reload(9))
	gadget.simulate(9)
	assert_eq(gadget.charges, 2)
	assert_eq(gadget.next_use_tick, 11)
	assert_eq(_uses, [10])
	assert_true(gadget.use(_ctx(11)))


func test_skipped_ticks_finish_reload_without_replaying_uses() -> void:
	var gadget: Gadget = _gadget(1)
	gadget.use(_ctx(0))
	gadget.reload(1)
	assert_true(gadget.use(_ctx(500)))
	assert_eq(_finishes, 1)
	assert_eq(_uses, [0, 500])
	assert_eq(gadget.charges, 0)
	assert_eq(gadget.next_use_tick, 530)


func test_fractional_durations_round_up_at_configured_tick_rate() -> void:
	var gadget: Gadget = _gadget(2, 0.11, 0.11)
	gadget.use(_ctx(0))
	assert_eq(gadget.next_use_tick, 7)
	gadget.reload(1)
	assert_eq(gadget.reload_end_tick, 8)
	gadget.simulate(7)
	assert_eq(gadget.charges, 1)
	gadget.simulate(8)
	assert_eq(gadget.charges, 2)


func test_zero_durations_still_require_one_tick() -> void:
	var gadget: Gadget = _gadget(2, 0.0, 0.0)
	gadget.use(_ctx(0))
	assert_eq(gadget.next_use_tick, 1)
	assert_true(gadget.reload(1))
	assert_eq(gadget.reload_end_tick, 2)
	assert_false(gadget.use(_ctx(1)))
	assert_true(gadget.use(_ctx(2)))


func test_zero_charges_null_context_and_negative_tick_are_safe() -> void:
	var gadget: Gadget = _gadget(0)
	assert_false(gadget.use(null))
	assert_false(gadget.use(_ctx(-1)))
	assert_false(gadget.reload(-1))
	assert_false(gadget.use(_ctx(0)))
	assert_false(gadget.reload(1))
	assert_eq(_uses, [])
	assert_eq(gadget.charges, 0)


func test_instances_share_data_without_sharing_state_or_refilling_on_setup() -> void:
	var first: Gadget = _gadget()
	var second: Gadget = Gadget.new()
	second.data = first.data
	add_child_autofree(second)
	first.use(_ctx(0))
	assert_false(first.setup(first.data))
	assert_eq(first.charges, 1)
	assert_eq(second.charges, 2)
	assert_eq(first.data.max_charges, 2)


func test_invalid_profiles_and_missing_data_are_rejected() -> void:
	var gadget: Gadget = Gadget.new()
	add_child_autofree(gadget)
	assert_false(gadget.setup(null))
	assert_false(gadget.use(_ctx(0)))
	var profile: GadgetData = GadgetData.new()
	profile.max_charges = -1
	assert_false(gadget.setup(profile))
	profile.max_charges = 1
	for invalid: float in [-1.0, INF, NAN]:
		profile.cooldown = invalid
		assert_false(gadget.setup(profile))
		profile.cooldown = 0.0
		profile.reload_time = invalid
		assert_false(gadget.setup(profile))
		profile.reload_time = 0.0
	gadget.ticks_per_second = 0
	assert_false(gadget.setup(profile))


func test_detached_gadget_cannot_initialize_or_simulate() -> void:
	var gadget: Gadget = Gadget.new()
	assert_false(gadget.setup(load(PROFILE) as GadgetData))
	assert_false(gadget.use(_ctx(0)))
	assert_false(gadget.reload(0))
	gadget.free()
