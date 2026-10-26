extends GutTest

const DELTA: float = 1.0 / 60.0

var _player: Player
var _hud: HUD
var _inp: PlayerInput


func before_each() -> void:
	var bed: Node3D = (load("res://src/maps/testbed/testbed.tscn") as PackedScene).instantiate() as Node3D
	_player = bed.get_node("Player") as Player
	_hud = bed.get_node("HUD") as HUD
	add_child_autofree(bed)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.release_mouse()
	_inp = PlayerInput.new()
	for tick: int in range(15):
		await get_tree().physics_frame
		_step()


func _step(slot: int = 0, buttons: int = 0, last: bool = false) -> void:
	_inp.tick += 1
	_inp.weapon_slot = slot
	_inp.buttons = buttons
	_inp.last_weapon = last
	_player.step_simulation(_inp, DELTA)
	_player.update_camera_visuals(DELTA)


func _finish_switch() -> void:
	while _player.inventory.phase != Inventory.Phase.READY:
		_step()


func test_player_switch_rebinds_hitscan_hud_supply_ads_and_cached_models() -> void:
	var primary: Weapon = _player.weapon
	var secondary: Weapon = _player.inventory.weapon_at(2)
	var primary_hitscan: WeaponHitscan = _player.weapon_hitscan
	var primary_model: Node3D = _player.ads_view.model
	var model_count: int = _player.ads_view.get_child_count()
	primary.ammo_in_mag = 11
	primary.reserve_ammo = 29
	secondary.ammo_in_mag = 4
	secondary.reserve_ammo = 5
	_step(2, PlayerInput.BTN_AIM)
	_finish_switch()
	assert_eq(_player.weapon, secondary)
	assert_ne(_player.weapon_hitscan, primary_hitscan)
	assert_eq(_hud.current_ammo, 4)
	assert_eq(_hud.reserve_ammo, 5)
	assert_ne(_player.ads_view.model, primary_model)
	assert_false(primary_model.visible)
	assert_eq(_player.ads_view.get_child_count(), model_count)
	assert_eq(_player.ads.target, 0.0)
	var receiver: AmmoReceiver = _player.get_node("AmmoReceiver") as AmmoReceiver
	assert_eq(receiver.weapon, secondary)
	assert_gt(receiver.add_ammo(0.1), 0)
	assert_eq(_hud.reserve_ammo, secondary.reserve_ammo)
	assert_eq(primary.reserve_ammo, 29)
	_step(0, 0, true)
	_finish_switch()
	assert_eq(_player.weapon, primary)
	assert_eq(_player.weapon_hitscan, primary_hitscan)
	assert_eq(_player.ads_view.model, primary_model)
	assert_eq(_player.ads_view.get_child_count(), model_count)
	assert_eq(_hud.current_ammo, 11)
	assert_eq(_hud.reserve_ammo, 29)
	assert_eq(primary.ammo_changed.get_connections().size(), 1)
	assert_eq(secondary.ammo_changed.get_connections().size(), 0)
	print("ACCEPT 2.7: AR -> pistol -> last AR; ammo 11/29 and 4/5 preserved; cached models reused")


func test_switch_with_held_fire_has_no_ray_until_draw_is_complete() -> void:
	var shots: Array[int] = []
	_player.weapon_hitscan.shot_traced.connect(
		func(tick: int, _pellet: int, _direction: Vector3, _hit: HitResult) -> void: shots.append(tick))
	_step(2, PlayerInput.BTN_FIRE)
	assert_eq(shots.size(), 0)
	while _player.inventory.phase == Inventory.Phase.HOLSTERING:
		_step(0, PlayerInput.BTN_FIRE)
	var secondary: Weapon = _player.weapon
	var secondary_shots: Array[int] = []
	_player.weapon_hitscan.shot_traced.connect(
		func(tick: int, _pellet: int, _direction: Vector3, _hit: HitResult) -> void:
			secondary_shots.append(tick))
	var end_tick: int = _player.inventory.end_tick
	while _inp.tick < end_tick - 1:
		_step(0, PlayerInput.BTN_FIRE)
	assert_eq(shots.size(), 0)
	assert_eq(secondary_shots.size(), 0)
	_step()
	_step(0, PlayerInput.BTN_FIRE)
	assert_eq(secondary_shots.size(), 1)
	assert_eq(secondary.ammo_in_mag, secondary.data.mag_size - 1)


func test_equipment_selection_clears_weapon_ui_and_last_restores_primary() -> void:
	var loadout: Loadout = _player.inventory.loadout.duplicate() as Loadout
	loadout.gadget_1 = EquipmentData.new()
	_player.inventory.loadout = loadout
	_step(3)
	_finish_switch()
	assert_null(_player.weapon)
	assert_null(_player.weapon_hitscan)
	assert_eq(_hud.current_ammo, 0)
	assert_eq(_hud.reserve_ammo, 0)
	assert_false(_player.ads_view.visible)
	_step(0, PlayerInput.BTN_AIM | PlayerInput.BTN_FIRE)
	assert_eq(_player.ads.target, 0.0)
	_step(0, 0, true)
	_finish_switch()
	assert_eq(_player.weapon, _player.inventory.weapon_at(1))
	assert_true(_player.ads_view.visible)
	assert_eq(_hud.current_ammo, _player.weapon.ammo_in_mag)


func test_actual_key_event_reaches_inventory_and_death_rejects_switch() -> void:
	_player.capture_mouse()
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_2
	key.pressed = true
	_player.handle_input_event(key)
	var inp: PlayerInput = _player.input_reader.read_input()
	inp.tick = _inp.tick + 1
	_player.step_simulation(inp, DELTA)
	assert_eq(_player.inventory.phase, Inventory.Phase.HOLSTERING)
	_inp.tick = inp.tick
	_finish_switch()
	(_player.health_component as HealthComponent).apply_damage(1000.0)
	_step(1)
	assert_eq(_player.inventory.phase, Inventory.Phase.READY)
	assert_eq(_player.inventory.active_slot, 2)
	_player.release_mouse()
