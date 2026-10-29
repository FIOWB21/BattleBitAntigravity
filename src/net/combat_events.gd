# Reliable server events. Clients only update replicas and forward Events to UI.
class_name CombatEvents
extends Node

var players: NetworkPlayers
var _spawn_ticks: Dictionary[int, int] = {}
var _state_ticks: Dictionary[int, int] = {}


func track(actor: Player) -> void:
	_spawn_ticks[actor.network_owner_id] = -1
	if not multiplayer.is_server():
		actor_ready.rpc_id(Net.SERVER_ID, actor.network_owner_id)
		return
	var health: HealthComponent = actor.health_component as HealthComponent
	health.damage_resolved.connect(_damage.bind(actor))
	health.health_changed.connect(_health_changed.bind(actor))
	actor.life.state_changed.connect(_life_changed.bind(actor))
	actor.life.finally_died.connect(_death.bind(actor))
	Events.player_spawned.emit(actor.network_owner_id)


func untrack(actor: Player) -> void:
	var health: HealthComponent = actor.health_component as HealthComponent
	if health.damage_resolved.is_connected(_damage.bind(actor)):
		health.damage_resolved.disconnect(_damage.bind(actor))
		health.health_changed.disconnect(_health_changed.bind(actor))
		actor.life.state_changed.disconnect(_life_changed.bind(actor))
		actor.life.finally_died.disconnect(_death.bind(actor))
	_spawn_ticks.erase(actor.network_owner_id)
	_state_ticks.erase(actor.network_owner_id)


@rpc("any_peer", "call_remote", "reliable", 0)
func actor_ready(id: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and players.ready_peers.has(sender) and players.actors.has(id):
		_send_state(players.actors[id], sender)


func _health_changed(current: float, _maximum: float, actor: Player) -> void:
	if current > 0.0:
		_sync(actor)


func _life_changed(_state: PlayerLife.State, actor: Player) -> void:
	_sync(actor)


func _sync(actor: Player) -> void:
	if not multiplayer.is_server() or players.respawns.spawning:
		return
	for recipient: int in players.ready_peers:
		if recipient != Net.SERVER_ID:
			_send_state(actor, recipient)


func _send_state(actor: Player, recipient: int) -> void:
	var health: HealthComponent = actor.health_component as HealthComponent
	life_sync.rpc_id(recipient, actor.network_owner_id, health.current, health.max_health,
		actor.life.state, actor.life.bleedout_remaining, health.protection_until_tick,
		players.respawns.spawn_ticks[actor.network_owner_id], actor.global_transform, Net.tick)


@rpc("authority", "call_remote", "reliable", 0)
func life_sync(id: int, current: float, maximum: float, state: int, bleedout: float,
		protection: int, spawn_tick: int, pose: Transform3D, server_tick: int) -> void:
	if multiplayer.is_server() or not players.actors.has(id) \
			or server_tick < maxi(_state_ticks.get(id, -1), _spawn_ticks.get(id, -1)):
		return
	var actor: Player = players.actors[id]
	var appeared: bool = spawn_tick > _spawn_ticks.get(id, -1)
	if appeared:
		_apply_spawn(actor, pose, spawn_tick)
	_state_ticks[id] = server_tick
	(actor.health_component as HealthComponent).protection_until_tick = protection
	actor.life.sync_replica(state as PlayerLife.State, current, maximum, bleedout)
	if appeared:
		Events.player_spawned.emit(id)


func _damage(source: int, zone: int, actor: Player) -> void:
	if not multiplayer.is_server():
		return
	var killed: bool = actor.life.state >= PlayerLife.State.DEAD
	if players.ready_peers.has(source):
		if source == Net.SERVER_ID:
			Events.hit_confirmed.emit(zone, killed)
		else:
			hit_confirm.rpc_id(source, zone, killed)
	var health: HealthComponent = actor.health_component as HealthComponent
	var origin: Vector3 = health.last_origin
	if not origin.is_finite() and players.actors.has(source):
		origin = players.actors[source].head.global_position
	var direction: Vector3 = (origin - actor.head.global_position).normalized() if origin.is_finite() else Vector3.ZERO
	if actor.network_owner_id == Net.SERVER_ID:
		Events.damage_indicated.emit(direction)
	elif players.ready_peers.has(actor.network_owner_id):
		damage_indicator.rpc_id(actor.network_owner_id, direction)
	_sync(actor)


@rpc("authority", "call_remote", "reliable", 0)
func hit_confirm(zone: int, killed: bool) -> void:
	if not multiplayer.is_server():
		Events.hit_confirmed.emit(zone, killed)


@rpc("authority", "call_remote", "reliable", 0)
func damage_indicator(direction: Vector3) -> void:
	if not multiplayer.is_server():
		Events.damage_indicated.emit(direction)


func _death(killer: int, actor: Player) -> void:
	if not multiplayer.is_server():
		return
	var health: HealthComponent = actor.health_component as HealthComponent
	var headshot: bool = health.last_zone == HitboxZone.HEAD
	for recipient: int in players.ready_peers:
		if recipient != Net.SERVER_ID:
			player_died.rpc_id(recipient, actor.network_owner_id, killer, health.last_weapon, headshot)
	_publish_death(actor.network_owner_id, killer, health.last_weapon, headshot)


@rpc("authority", "call_remote", "reliable", 0)
func player_died(victim: int, killer: int, weapon: StringName, headshot: bool) -> void:
	if not multiplayer.is_server():
		_publish_death(victim, killer, weapon, headshot)


func _publish_death(victim: int, killer: int, weapon: StringName, headshot: bool) -> void:
	Events.player_died.emit(victim, killer, weapon, headshot)
	var actor: Player = players.actors.get(victim)
	if actor != null and actor.is_local_player:
		actor.local_controller.kill_target = players.actors.get(killer)


func respawned(actor: Player, tick: int) -> void:
	if not multiplayer.is_server():
		return
	for recipient: int in players.ready_peers:
		if recipient != Net.SERVER_ID:
			player_spawned.rpc_id(recipient, actor.network_owner_id, actor.global_transform, tick,
				actor.health_component.max_health, actor.health_component.protection_until_tick)
	Events.player_spawned.emit(actor.network_owner_id)
	_sync(actor)


@rpc("authority", "call_remote", "reliable", 0)
func player_spawned(id: int, pose: Transform3D, tick: int, maximum: float, protection: int) -> void:
	if not multiplayer.is_server() and players.actors.has(id) and tick > _spawn_ticks.get(id, -1):
		var actor: Player = players.actors[id]
		_apply_spawn(actor, pose, tick)
		(actor.health_component as HealthComponent).protection_until_tick = protection
		actor.life.sync_replica(PlayerLife.State.ALIVE, maximum, maximum, 0.0)
		_state_ticks[id] = tick
		Events.player_spawned.emit(id)


func _apply_spawn(actor: Player, pose: Transform3D, tick: int) -> void:
	_spawn_ticks[actor.network_owner_id] = tick
	actor.equipment.combat.reset_for_spawn(tick)
	actor.local_controller.kill_target = null
	SpawnState.apply_pose(actor, pose, tick)
