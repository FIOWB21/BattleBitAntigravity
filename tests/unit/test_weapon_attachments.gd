extends GutTest

var _weapon: Weapon
var _base: WeaponData


func before_each() -> void:
	_base = WeaponData.new()
	_weapon = Weapon.new()
	_weapon.data = _base
	add_child_autofree(_weapon)


func test_repeated_equip_replaces_slot_without_compounding_or_refilling() -> void:
	_weapon.ammo_in_mag = 7
	_weapon.reserve_ammo = 19
	for repeat: int in range(50):
		assert_true(_weapon.attachments.equip(AttachmentCommand.PROFILES["grip"]))
		assert_eq(_weapon.attachments.items().size(), 1)
		assert_almost_eq(_weapon.data.spread_hip_deg, _base.spread_hip_deg * 0.8, 0.000001)
		assert_eq(_weapon.ammo_in_mag, 7)
		assert_eq(_weapon.reserve_ammo, 19)
	assert_true(_weapon.attachments.remove(AttachmentData.Slot.GRIP))
	assert_eq(_weapon.data.spread_hip_deg, _base.spread_hip_deg)
	assert_false(_weapon.attachments.remove(AttachmentData.Slot.GRIP))
	assert_eq(_weapon.ammo_in_mag, 7)


func test_same_slot_replacement_and_public_array_cannot_add_duplicate() -> void:
	var replacement: AttachmentData = AttachmentCommand.PROFILES["grip"].duplicate() as AttachmentData
	replacement.modifiers = []
	assert_true(_weapon.attachments.equip(AttachmentCommand.PROFILES["grip"]))
	assert_true(_weapon.attachments.equip(replacement))
	assert_eq(_weapon.data.spread_hip_deg, _base.spread_hip_deg)
	var public_items: Array[AttachmentData] = _weapon.attachments.items()
	public_items.clear()
	assert_eq(_weapon.attachments.items().size(), 1)


func test_rejected_transaction_keeps_previous_data_and_items() -> void:
	assert_true(_weapon.attachments.equip(AttachmentCommand.PROFILES["grip"]))
	var previous: WeaponData = _weapon.data
	var invalid: AttachmentData = AttachmentData.new()
	var modifier: AttachmentModifier = AttachmentModifier.new()
	modifier.stat = &"not_a_stat"
	invalid.modifiers = [modifier]
	assert_false(_weapon.attachments.equip(invalid))
	assert_false(_weapon.attachments.equip(null))
	assert_eq(_weapon.data, previous)
	assert_eq(_weapon.attachments.items().size(), 1)


func test_busy_states_cannot_change_attachments() -> void:
	for state: Weapon.State in [Weapon.State.FIRING, Weapon.State.RELOADING,
			Weapon.State.SWITCHING_IN, Weapon.State.SWITCHING_OUT, Weapon.State.BLOCKED]:
		_weapon.state = state
		assert_false(_weapon.attachments.equip(AttachmentCommand.PROFILES["magazine"]))
		assert_eq(_weapon.data, _base)
	assert_eq(_weapon.attachments.items().size(), 0)


func test_magazine_removal_moves_excess_into_reserve_without_losing_or_creating_ammo() -> void:
	assert_true(_weapon.attachments.equip(AttachmentCommand.PROFILES["magazine"]))
	assert_eq(_weapon.ammo_in_mag, 30)
	_weapon.ammo_in_mag = 41
	_weapon.reserve_ammo = 200
	var events: Array[Vector2i] = []
	_weapon.ammo_changed.connect(func(mag: int, reserve: int) -> void: events.append(Vector2i(mag, reserve)))
	assert_true(_weapon.attachments.remove(AttachmentData.Slot.MAGAZINE))
	assert_eq(_weapon.ammo_in_mag, 31)
	assert_eq(_weapon.reserve_ammo, 210)
	assert_eq(events, [Vector2i(31, 210)])
	assert_eq(_weapon.ammo_in_mag + _weapon.reserve_ammo, 241)


func test_no_chamber_limits_loaded_rounds_to_base_capacity() -> void:
	_base.chamber_enabled = false
	assert_true(_weapon.attachments.equip(AttachmentCommand.PROFILES["magazine"]))
	_weapon.ammo_in_mag = 40
	assert_true(_weapon.attachments.remove(AttachmentData.Slot.MAGAZINE))
	assert_eq(_weapon.ammo_in_mag, 30)
	assert_eq(_weapon.reserve_ammo, 160)


func test_attachment_change_preserves_tick_cooldown_and_fire_mode() -> void:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 20
	_weapon.simulate(inp)
	_weapon.next_fire_tick = 40
	_weapon.fire_mode = WeaponData.FireMode.SEMI
	assert_true(_weapon.attachments.equip(AttachmentCommand.PROFILES["muzzle"]))
	assert_eq(_weapon.next_fire_tick, 40)
	assert_eq(_weapon.fire_mode, WeaponData.FireMode.SEMI)
	inp.buttons = PlayerInput.BTN_FIRE
	_weapon.simulate(inp)
	assert_eq(_weapon.ammo_in_mag, 30)
	inp.tick = 21
	_weapon.simulate(inp)
	assert_eq(_weapon.ammo_in_mag, 30)


func test_setup_clears_old_attachments_without_mutating_either_profile() -> void:
	assert_true(_weapon.attachments.equip(AttachmentCommand.PROFILES["magazine"]))
	var replacement: WeaponData = WeaponData.new()
	replacement.mag_size = 12
	_weapon.setup(replacement)
	assert_eq(_weapon.attachments.items().size(), 0)
	assert_true(_weapon.attachments.equip(AttachmentCommand.PROFILES["grip"]))
	assert_eq(_weapon.data.mag_size, 12)
	assert_eq(_base.mag_size, 30)
	assert_eq(replacement.spread_hip_deg, 2.0)


func test_client_cannot_equip_or_remove() -> void:
	assert_true(_weapon.attachments.equip(AttachmentCommand.PROFILES["grip"]))
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 9), OK)
	api.multiplayer_peer = peer
	var path: NodePath = _weapon.get_path()
	get_tree().set_multiplayer(api, path)
	assert_false(_weapon.attachments.equip(AttachmentCommand.PROFILES["magazine"]))
	assert_false(_weapon.attachments.remove(AttachmentData.Slot.GRIP))
	assert_eq(_weapon.attachments.items().size(), 1)
	assert_eq(_weapon.data.mag_size, 30)
	get_tree().set_multiplayer(null, path)
	peer.close()
