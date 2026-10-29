# One authoritative deadline per existing actor; no new Player is instantiated.
class_name RespawnService
extends Node

signal player_respawned(actor: Player, tick: int)

var players: NetworkPlayers
var spawning: bool = false
var spawn_ticks: Dictionary[int, int] = {}
var deadlines: Dictionary[int, int] = {}
var _actors: Array[Player] = []


func _ready() -> void:
	process_physics_priority = -50


func track(actor: Player) -> void:
	actor.life.network_respawn_managed = true
	_actors.append(actor)
	spawn_ticks[actor.network_owner_id] = Net.tick
	actor.life.finally_died.connect(_schedule.bind(actor))


func untrack(actor: Player) -> void:
	actor.life.finally_died.disconnect(_schedule.bind(actor))
	_actors.erase(actor)
	deadlines.erase(actor.network_owner_id)
	spawn_ticks.erase(actor.network_owner_id)


func _schedule(_killer: int, actor: Player) -> void:
	if not multiplayer.is_server() or deadlines.has(actor.network_owner_id):
		return
	deadlines[actor.network_owner_id] = Net.tick + ceili(
		actor.life.rules.respawn_delay * Engine.physics_ticks_per_second)


func _physics_process(_delta: float) -> void:
	step(Net.tick)


func step(tick: int) -> void:
	if not multiplayer.is_server():
		return
	for actor: Player in _actors:
		var id: int = actor.network_owner_id
		if deadlines.has(id) and tick >= deadlines[id]:
			deadlines.erase(id)
			if actor.life.state == PlayerLife.State.SPAWN_SELECT:
				_spawn(actor, tick)


func _spawn(actor: Player, tick: int) -> void:
	spawning = true
	var pose: Transform3D = players.respawn_pose(actor.network_owner_id)
	var health: HealthComponent = actor.health_component as HealthComponent
	health.protection_until_tick = tick + ceili(actor.life.rules.spawn_protection * Engine.physics_ticks_per_second)
	actor.server_sim.input_queue.reset_for_spawn(tick, pose.basis.get_euler().y)
	actor.equipment.combat.reset_for_spawn(actor.server_sim.input_queue.last_input_tick)
	players.lag_compensator.reset_player(actor)
	SpawnState.refill(actor)
	actor.life.spawn_at(pose, true)
	SpawnState.apply_pose(actor, pose, tick)
	spawn_ticks[actor.network_owner_id] = tick
	spawning = false
	player_respawned.emit(actor, tick)
