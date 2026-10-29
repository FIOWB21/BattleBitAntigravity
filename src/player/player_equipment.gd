# Связывает инвентарь с уже существующими симуляцией и представлением игрока.
class_name PlayerEquipment
extends Node

var _player: Player
var _receiver: AmmoReceiver
var _hitscans: Dictionary[Weapon, WeaponHitscan] = {}
var effects: ShotEffects
var projectiles: PlayerProjectiles
var melee: MeleeAttack
var melee_view: MeleeView
var gadgets: PlayerGadgets
var combat: NetworkCombat


func setup(player: Player) -> void:
	_player = player
	_receiver = player.get_node_or_null("AmmoReceiver") as AmmoReceiver
	var inventory: Inventory = player.inventory
	var exclude: Array[RID] = player.get_hitscan_exclude_rids()
	_setup_effects()
	projectiles = PlayerProjectiles.new()
	add_child(projectiles)
	projectiles.setup(player)
	_setup_melee()
	gadgets = PlayerGadgets.new()
	add_child(gadgets)
	gadgets.setup(player)
	for slot: int in range(1, Loadout.SLOT_COUNT + 1):
		var weapon: Weapon = inventory.weapon_at(slot)
		if weapon == null:
			continue
		var hitscan: WeaponHitscan = player.weapon_hitscan if weapon == player.weapon else null
		if hitscan == null:
			hitscan = WeaponHitscan.new()
			add_child(hitscan)
		var attacker: int = player.network_owner_id if player.network_owner_id != 0 else player.get_multiplayer_authority()
		hitscan.setup(weapon, attacker, exclude)
		hitscan.projectiles = projectiles.system
		_hitscans[weapon] = hitscan
		if effects != null:
			effects.bind_weapon(weapon, hitscan)
		if player.ads_view != null:
			player.ads_view.cache_weapon(weapon, player.is_local_player)
	inventory.active_slot_changed.connect(_on_active_slot_changed)
	_on_active_slot_changed(inventory.active_slot, inventory.active_weapon())
	_setup_combat()


func _setup_combat() -> void:
	if _player.network_owner_id != 0:
		combat = NetworkCombat.new()
		combat.name = "NetworkCombat"
		add_child(combat)
		combat.setup(_player)


func _setup_melee() -> void:
	melee = MeleeAttack.new()
	melee.name = "MeleeAttack"
	add_child(melee)
	var exclude: Array[RID] = _player.get_hitscan_exclude_rids().duplicate()
	if not exclude.has(_player.get_rid()):
		exclude.append(_player.get_rid())
	var attacker: int = _player.network_owner_id if _player.network_owner_id != 0 else _player.get_multiplayer_authority()
	melee.setup(attacker, exclude)
	if _player.is_local_player and not Game.is_dedicated:
		melee_view = MeleeView.new()
		melee_view.name = "MeleeView"
		_player.camera.add_child(melee_view)
		melee_view.setup(melee, _player.ads_view)


func simulate_melee(inp: PlayerInput) -> void:
	var alive: bool = not (_player.health_component is HealthComponent and _player.health_component.is_dead)
	var allowed: bool = _player.inventory.phase == Inventory.Phase.READY
	if _player.weapon != null:
		allowed = allowed and _player.weapon.state != Weapon.State.RELOADING
	var aim: Transform3D = Transform3D(Basis.from_euler(Vector3(
		_player.head.rotation.x, inp.yaw, _player.head.rotation.z)), _player.head.global_position)
	melee.simulate(inp, aim, _player.global_position, alive, allowed)
	gadgets.simulate(inp)


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
		_player.weapon.stats_changed.disconnect(_update_stats)
	_player.weapon = weapon
	_player.weapon_hitscan = _hitscans.get(weapon) as WeaponHitscan if weapon != null else null
	if weapon != null:
		weapon.configured.connect(_reset_ads)
		weapon.stats_changed.connect(_update_stats)
	if _receiver != null:
		_receiver.weapon = weapon
	_reset_ads()
	if _player.ads_view != null:
		_player.ads_view.setup(weapon, _player.is_local_player)


func _reset_ads() -> void:
	_player.ads.setup(_player.weapon.data if _player.weapon != null else null)
	_player.input_reader.aim_sensitivity_scale = 1.0


func _update_stats() -> void:
	_player.ads.update_data(_player.weapon.data)
