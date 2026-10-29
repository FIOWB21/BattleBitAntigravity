# Unreliable cosmetic events are separate from owner-only reliable ammunition.
class_name WeaponPresentation
extends Node3D

signal shot_presented(peer_id: int, tick: int, weapon_id: int)

const SHOT_BYTES: int = 12

@export var config: ShotFxConfig = preload("res://src/fx/default_shot_fx.tres")

var players: NetworkPlayers
var flashes: ObjectPool
var audio: ShotAudio
var presented_shots: int = 0
var sent_events: int = 0
var delay: NetSim
var _packet: PackedByteArray = PackedByteArray()
var _assets: ShotFxAssets
var _last_shots: Dictionary[int, int] = {}
var _bindings: Dictionary[Weapon, Callable] = {}


func _ready() -> void:
	delay = NetSim.new()
	delay.configure(SHOT_BYTES)
	delay.packet_delivered.connect(_transmit_shot)
	add_child(delay)
	_packet.resize(SHOT_BYTES)
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
	delay.discard_peer(actor.network_owner_id)
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
	_packet.encode_u32(0, owner)
	_packet.encode_u32(4, tick)
	_packet.encode_u32(8, id)
	if not Game.is_dedicated and not actor.is_local_player:
		present_shot(owner, tick, id)
	for recipient: int in players.ready_peers:
		if recipient != owner and recipient != Net.SERVER_ID and Net.nicknames.has(recipient):
			delay.submit(_packet, PackedByteArray(), recipient)
			sent_events += 1


func _transmit_shot(packet: PackedByteArray, _extra: PackedByteArray, peer_id: int) -> void:
	if Net.is_connected and players.ready_peers.has(peer_id) and Net.time_sync.can_send(peer_id):
		remote_shot.rpc_id(peer_id, packet.decode_u32(0), packet.decode_u32(4), packet.decode_u32(8))


@rpc("authority", "call_remote", "unreliable", 3)
func remote_shot(peer_id: int, tick: int, id: int) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != Net.SERVER_ID:
		return
	Net.note_packet(Net.SERVER_ID)
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
	delay.clear()
	_last_shots.clear()
	if audio == null:
		return
	for voice: AudioStreamPlayer3D in audio.pool.items:
		voice.stop()
	for flash: MuzzleFlash in flashes.items:
		flash.advance(config.flash_lifetime, Engine.get_process_frames() + 1)
