# Unreliable cosmetic events are separate from owner-only reliable ammunition.
class_name WeaponPresentation
extends Node3D

signal shot_presented(peer_id: int, tick: int, weapon_id: int)

@export var config: ShotFxConfig = preload("res://src/fx/default_shot_fx.tres")

var players: NetworkPlayers
var flashes: ObjectPool
var audio: ShotAudio
var presented_shots: int = 0
var sent_events: int = 0
var _assets: ShotFxAssets
var _last_shots: Dictionary[int, int] = {}
var _bindings: Dictionary[Weapon, Callable] = {}


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(false)
	if Game.is_dedicated:
		return
	_assets = ShotFxAssets.new()
	_assets.build(config)
	flashes = ObjectPool.new()
	add_child(flashes)
	flashes.prewarm(config.flash_capacity, _create_flash)
	audio = ShotAudio.new()
	add_child(audio)
	audio.setup(config)
	set_process(true)


func _create_flash() -> MuzzleFlash:
	var flash: MuzzleFlash = MuzzleFlash.new()
	flash.setup(config, _assets)
	return flash


func track(actor: Player) -> void:
	_last_shots[actor.network_owner_id] = -1
	if not multiplayer.is_server():
		return
	for slot: int in range(1, Loadout.SLOT_COUNT + 1):
		var weapon: Weapon = actor.inventory.weapon_at(slot)
		if weapon != null:
			var callback: Callable = _fired.bind(actor, weapon.data.id.hash() & SnapshotCodec.UINT_MAX)
			_bindings[weapon] = callback
			weapon.fired.connect(callback)


func untrack(actor: Player) -> void:
	_last_shots.erase(actor.network_owner_id)
	for slot: int in range(1, Loadout.SLOT_COUNT + 1):
		var weapon: Weapon = actor.inventory.weapon_at(slot)
		if weapon != null and _bindings.has(weapon):
			weapon.fired.disconnect(_bindings[weapon])
			_bindings.erase(weapon)


func _fired(tick: int, actor: Player, id: int) -> void:
	if not multiplayer.is_server() or not Net.is_connected:
		return
	var owner: int = actor.network_owner_id
	if not Game.is_dedicated and not actor.is_local_player:
		present_shot(owner, tick, id)
	for recipient: int in players.ready_peers:
		if recipient != owner and recipient != Net.SERVER_ID and Net.nicknames.has(recipient):
			remote_shot.rpc_id(recipient, owner, tick, id)
			sent_events += 1


@rpc("authority", "call_remote", "unreliable", 3)
func remote_shot(peer_id: int, tick: int, id: int) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != Net.SERVER_ID:
		return
	present_shot(peer_id, tick, id)


func present_shot(peer_id: int, tick: int, id: int) -> bool:
	var actor: Player = players.actors.get(peer_id)
	if actor == null or audio == null or tick <= _last_shots.get(peer_id, -1):
		return false
	var view: WorldWeaponView = actor.remote_view.weapon_view
	if view == null or not actor.remote_view.accepts_shot(tick) or not view.has_weapon(id):
		return false
	_last_shots[peer_id] = tick
	var pose: Transform3D = view.muzzle_pose(id)
	var flash: MuzzleFlash = flashes.acquire() as MuzzleFlash
	if flash != null:
		flash.pulse(pose, Engine.get_process_frames())
	var sound: AudioStream = view.fire_sound(id)
	audio.play_at(sound if sound != null else _assets.fire_sound, pose.origin)
	view.shot_presented()
	presented_shots += 1
	shot_presented.emit(peer_id, tick, id)
	return true


func _process(delta: float) -> void:
	for flash: MuzzleFlash in flashes.items:
		flash.advance(delta, Engine.get_process_frames())


func reset() -> void:
	_last_shots.clear()
	if audio == null:
		return
	for voice: AudioStreamPlayer3D in audio.pool.items:
		voice.stop()
	for flash: MuzzleFlash in flashes.items:
		flash.advance(config.flash_lifetime, Engine.get_process_frames() + 1)
