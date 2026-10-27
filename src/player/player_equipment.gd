# Связывает инвентарь с уже существующими симуляцией и представлением игрока.
class_name PlayerEquipment
extends Node

var _player: Player
var _receiver: AmmoReceiver
var _hitscans: Dictionary[Weapon, WeaponHitscan] = {}
var effects: ShotEffects


func setup(player: Player) -> void:
	_player = player
	_receiver = player.get_node_or_null("AmmoReceiver") as AmmoReceiver
	var inventory: Inventory = player.inventory
	var exclude: Array[RID] = player.get_hitscan_exclude_rids()
	_setup_effects()
	for slot: int in range(1, Loadout.SLOT_COUNT + 1):
		var weapon: Weapon = inventory.weapon_at(slot)
		if weapon == null:
			continue
		var hitscan: WeaponHitscan = player.weapon_hitscan if weapon == player.weapon else null
		if hitscan == null:
			hitscan = WeaponHitscan.new()
			add_child(hitscan)
		hitscan.setup(weapon, player.get_multiplayer_authority(), exclude)
		_hitscans[weapon] = hitscan
		if effects != null:
			effects.bind_weapon(weapon, hitscan)
		if player.ads_view != null:
			player.ads_view.cache_weapon(weapon, player.is_local_player)
	inventory.active_slot_changed.connect(_on_active_slot_changed)
	_on_active_slot_changed(inventory.active_slot, inventory.active_weapon())


func _setup_effects() -> void:
	if Game.is_dedicated:
		return
	effects = ShotEffects.new()
	effects.name = "ShotEffects"
	_player.add_child(effects)
	var listener: Camera3D = _player.camera if _player.is_local_player else get_viewport().get_camera_3d()
	effects.setup(listener, _player.is_local_player, _player.ads_view)


func _on_active_slot_changed(_slot: int, weapon: Weapon) -> void:
	if _player.weapon != null and _player.weapon.configured.is_connected(_reset_ads):
		_player.weapon.configured.disconnect(_reset_ads)
	_player.weapon = weapon
	_player.weapon_hitscan = _hitscans.get(weapon) as WeaponHitscan if weapon != null else null
	if weapon != null:
		weapon.configured.connect(_reset_ads)
	if _receiver != null:
		_receiver.weapon = weapon
	_reset_ads()
	if _player.ads_view != null:
		_player.ads_view.setup(weapon, _player.is_local_player)


func _reset_ads() -> void:
	_player.ads.setup(_player.weapon.data if _player.weapon != null else null)
	_player.input_reader.aim_sensitivity_scale = 1.0
