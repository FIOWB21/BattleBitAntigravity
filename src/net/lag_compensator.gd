# World-owned server history. Only physics hitboxes move, never player bodies/views.
class_name LagCompensator
extends Node

const HISTORY: int = 60
const MAX_REWIND_SECONDS: float = 0.25

var tracks: Array[LagTrack] = []
var active: bool = false
var last_rewind_tick: int = -1
var _recorded_tick: int = -1


func _ready() -> void:
	process_physics_priority = 50


func track(actor: Player) -> void:
	if not multiplayer.is_server():
		return
	var entry: LagTrack = LagTrack.new()
	entry.configure(actor, HISTORY)
	tracks.append(entry)


func untrack(actor: Player) -> void:
	for index: int in range(tracks.size() - 1, -1, -1):
		if tracks[index].actor == actor:
			tracks[index].restore()
			tracks.remove_at(index)


func clear() -> void:
	restore()
	tracks.clear()
	_recorded_tick = -1
	last_rewind_tick = -1


func record(tick: int) -> void:
	if not multiplayer.is_server() or active or tick < 0 or tick <= _recorded_tick:
		return
	for entry: LagTrack in tracks:
		entry.record(tick)
	_recorded_tick = tick


func bounded_tick(now_tick: int, view_tick: int) -> int:
	var limit: int = floori(MAX_REWIND_SECONDS * Engine.physics_ticks_per_second)
	return clampi(view_tick, maxi(0, now_tick - limit), now_tick)


func rewind(now_tick: int, view_tick: int, shooter_id: int) -> bool:
	if not multiplayer.is_server() or active:
		return false
	last_rewind_tick = bounded_tick(now_tick, view_tick)
	active = true
	for entry: LagTrack in tracks:
		if entry.actor.network_owner_id != shooter_id:
			entry.rewind(last_rewind_tick)
	return true


func restore() -> void:
	for entry: LagTrack in tracks:
		entry.restore()
	active = false


func _physics_process(_delta: float) -> void:
	if not Net.is_connected or not multiplayer.is_server():
		return
	record(Net.tick)
	for entry: LagTrack in tracks:
		entry.actor.equipment.combat.physics_step()
