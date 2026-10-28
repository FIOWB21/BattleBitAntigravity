# Fire carries intent and a reproducible seed; all gameplay state stays on the server.
class_name NetworkCombat
extends Node

signal fire_accepted(input_tick: int, server_tick: int)
signal ammo_synchronized(magazine: int, reserve: int)

var player: Player
var history: FireHistory = FireHistory.new()
var accepted_shots: int = 0
var rejected_requests: int = 0
var sent_requests: int = 0
var _neutral: PlayerInput = PlayerInput.new()
var _local_tick: int = 0
var _recorded_tick: int = 0
var _sync_tick: int = -1
var _sync_interval: int
var _resolved_fire_tick: int = 0
var _pending_ticks: PackedInt64Array = PackedInt64Array()


func setup(actor: Player) -> void:
	player = actor
	history.configure(Net.config, Engine.physics_ticks_per_second)
	_pending_ticks.resize(history.frames.size())
	_pending_ticks.fill(0)
	_sync_interval = preload("res://src/net/default_snapshot.tres").interval_ticks
	for slot: int in range(1, Loadout.SLOT_COUNT + 1):
		var weapon: Weapon = player.inventory.weapon_at(slot)
		if weapon != null and not multiplayer.is_server():
			weapon.fired.connect(_predicted_fire)


func predict(inp: PlayerInput) -> void:
	if multiplayer.is_server() or not player.is_local_player or player.weapon_hitscan == null:
		return
	_local_tick = inp.tick
	var hitscan: WeaponHitscan = player.weapon_hitscan
	hitscan.cosmetic_only = true
	hitscan.shot_seed = FireHistory.shot_seed(inp.tick, player.network_owner_id)
	var aim: Transform3D = Transform3D(Basis.from_euler(Vector3(
		inp.pitch, inp.yaw, player.head.rotation.z)), player.head.global_position)
	var blocked: bool = player.motor.is_sprinting or not player.is_on_floor()
	blocked = blocked or (player.health_component as HealthComponent).is_dead
	blocked = blocked or player.inventory.phase != Inventory.Phase.READY
	hitscan.simulate(inp, aim, blocked, player.stance,
		Vector2(player.velocity.x, player.velocity.z).length(), player.motor.is_sprinting, player.ads.amount())
	hitscan.shot_seed = -1


func _predicted_fire(_tick: int) -> void:
	sent_requests += 1
	_pending_ticks[_local_tick % _pending_ticks.size()] = _local_tick
	fire.rpc_id(Net.SERVER_ID, _local_tick, FireHistory.shot_seed(_local_tick, player.network_owner_id))


@rpc("any_peer", "call_remote", "reliable", 0)
func fire(input_tick: int, seed: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != player.network_owner_id or not Net.nicknames.has(sender):
		rejected_requests += 1
		return
	if not history.request(input_tick, seed, sender, Net.tick):
		rejected_requests += 1


func simulate(inp: PlayerInput, aim: Transform3D, blocked: bool) -> void:
	var weapon: Weapon = player.weapon
	var hitscan: WeaponHitscan = player.weapon_hitscan
	if weapon == null or hitscan == null:
		return
	# Listen-host uses exactly the same authoritative Weapon simulation once.
	if player.network_owner_id == Net.SERVER_ID:
		hitscan.simulate(inp, aim, blocked, player.stance,
			Vector2(player.velocity.x, player.velocity.z).length(), player.motor.is_sprinting, player.ads.amount())
		return
	InputCodec.copy_into(inp, _neutral)
	_neutral.buttons &= ~PlayerInput.BTN_FIRE
	hitscan.simulate(_neutral, aim, blocked, player.stance,
		Vector2(player.velocity.x, player.velocity.z).length(), player.motor.is_sprinting, player.ads.amount())
	_record(weapon, hitscan, blocked)


func physics_step() -> void:
	var blocked: bool = player.motor.is_sprinting or not player.is_on_floor()
	blocked = blocked or (player.health_component as HealthComponent).is_dead
	_resolve(blocked)
	if Net.is_connected and Net.tick % _sync_interval == 0 and player.network_owner_id != Net.SERVER_ID:
		_send_ammo()


func _record(weapon: Weapon, hitscan: WeaponHitscan, blocked: bool) -> void:
	var input_tick: int = player.server_sim.input_queue.last_input_tick
	if input_tick <= _recorded_tick:
		return
	_recorded_tick = input_tick
	var frame: FireFrame = history.slot(input_tick)
	frame.weapon = weapon
	frame.hitscan = hitscan
	frame.aim = hitscan.aim_transform
	frame.spread = hitscan.spread
	frame.allowed = not blocked and player.inventory.phase == Inventory.Phase.READY
	frame.recorded = true


func _resolve(blocked: bool) -> void:
	for index: int in range(history.frames.size()):
		var frame: FireFrame = history.take_ready(Net.tick)
		_resolved_fire_tick = maxi(_resolved_fire_tick, history.expired_tick)
		if frame == null:
			return
		_resolved_fire_tick = maxi(_resolved_fire_tick, frame.tick)
		if blocked or not frame.allowed or frame.weapon != player.weapon:
			rejected_requests += 1
			continue
		if frame.hitscan.fire_requested(Net.tick, frame.seed, frame.aim, frame.spread):
			accepted_shots += 1
			fire_accepted.emit(frame.tick, Net.tick)
		else:
			rejected_requests += 1


func _send_ammo() -> void:
	var weapon: Weapon = player.weapon
	if not Net.nicknames.has(player.network_owner_id):
		return
	ammo_sync.rpc_id(player.network_owner_id, Net.tick, player.inventory.active_slot,
		weapon.ammo_in_mag if weapon != null else 0, weapon.reserve_ammo if weapon != null else 0,
		weapon.state if weapon != null else Weapon.State.BLOCKED, player.inventory.phase,
		maxi(0, weapon.next_fire_tick - Net.tick) if weapon != null else 0,
		maxi(0, weapon.reload_end_tick - Net.tick) if weapon != null else 0,
		maxi(0, weapon.switch_end_tick - Net.tick) if weapon != null else 0, _resolved_fire_tick)


@rpc("authority", "call_remote", "reliable", 0)
func ammo_sync(server_tick: int, slot: int, magazine: int, reserve: int,
		state: int, phase: int, cooldown: int, reload_ticks: int, switch_ticks: int, resolved_fire_tick: int) -> void:
	if multiplayer.is_server() or not player.is_local_player or server_tick <= _sync_tick:
		return
	var weapon: Weapon = player.inventory.weapon_at(slot)
	_sync_tick = server_tick
	if player.inventory.active_slot != slot:
		player.inventory.active_slot = slot
		player.inventory.active_slot_changed.emit(slot, weapon)
	player.inventory.phase = phase as Inventory.Phase
	if weapon == null:
		return
	weapon.ammo_in_mag = maxi(0, magazine - _pending_count(resolved_fire_tick))
	weapon.reserve_ammo = reserve
	weapon.sync_replica(state as Weapon.State, Net.tick, cooldown, reload_ticks, switch_ticks)
	weapon.ammo_changed.emit(magazine, reserve)
	ammo_synchronized.emit(magazine, reserve)


func _pending_count(resolved_fire_tick: int) -> int:
	var pending: int = 0
	for index: int in range(_pending_ticks.size()):
		if _pending_ticks[index] <= resolved_fire_tick:
			_pending_ticks[index] = 0
		elif _pending_ticks[index] > 0:
			pending += 1
	return pending
