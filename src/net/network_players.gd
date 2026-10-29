# Reliable presence; compact state transport is a separate world component.
class_name NetworkPlayers
extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://src/player/player.tscn")

var loader: MapLoader
var actors: Dictionary[int, Player] = {}
var ready_peers: Dictionary[int, bool] = {}
var snapshots: SnapshotStream
var lag_compensator: LagCompensator
var respawns: RespawnService
var combat_events: CombatEvents
var _slots: Dictionary[int, int] = {}
var _spawner: MultiplayerSpawner
var _container: Node3D


func _ready() -> void:
	_container = Node3D.new()
	_container.name = "Players"
	add_child(_container)
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "Spawner"
	_spawner.spawn_path = ^"../Players"
	_spawner.spawn_function = _spawn_player
	add_child(_spawner)
	snapshots = SnapshotStream.new()
	snapshots.name = "Snapshots"
	snapshots.players = self
	add_child(snapshots)
	lag_compensator = LagCompensator.new()
	lag_compensator.name = "LagCompensator"
	add_child(lag_compensator)
	respawns = RespawnService.new()
	respawns.name = "Respawns"
	respawns.players = self
	add_child(respawns)
	combat_events = CombatEvents.new()
	combat_events.name = "CombatEvents"
	combat_events.players = self
	add_child(combat_events)
	respawns.player_respawned.connect(combat_events.respawned)
	Net.peer_joined.connect(_peer_joined)
	Net.peer_left.connect(_peer_left)


func _peer_joined(id: int, _nickname: String) -> void:
	if id == Net.SERVER_ID and multiplayer.is_server() and loader.current_map != null:
		_admit(id)


@rpc("any_peer", "call_remote", "reliable", 0)
func map_ready(map_id: String) -> void:
	if not multiplayer.is_server() or loader.current_map == null:
		return
	var id: int = multiplayer.get_remote_sender_id()
	if id <= Net.SERVER_ID or not Net.nicknames.has(id) or map_id != String(loader.current_data.id):
		return
	_admit(id)


func _admit(id: int) -> void:
	if ready_peers.has(id):
		return
	ready_peers[id] = true
	for actor: Player in actors.values():
		(actor.get_node("Presence") as MultiplayerSynchronizer).set_visibility_for(id, true)
	var slot: int = 0
	while _slots.values().has(slot):
		slot += 1
	_slots[id] = slot
	var pose: Transform3D = loader.spawn_pose
	pose.origin += pose.basis * loader.current_data.spawn_offset(slot)
	_spawner.spawn({"peer_id": id, "nickname": Net.nicknames[id], "pose": global_transform.affine_inverse() * pose})


func _spawn_player(payload: Variant) -> Node:
	if not payload is Dictionary:
		return null
	var data: Dictionary = payload as Dictionary
	var id: int = int(data.get("peer_id", 0))
	if id < Net.SERVER_ID or actors.has(id) or not data.get("pose") is Transform3D:
		return null
	var actor: Player = PLAYER_SCENE.instantiate() as Player
	actor.name = str(id)
	if not multiplayer.is_server():
		Net.nicknames[id] = String(data.get("nickname", str(id)))
	actor.network_owner_id = id
	actor.is_local_player = id == multiplayer.get_unique_id() and not Game.is_dedicated
	actor.transform = data["pose"] as Transform3D
	actor.set_multiplayer_authority(Net.SERVER_ID)
	actor.get_node("LocalPlayerController").set_multiplayer_authority(id)
	var presence: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	presence.name = "Presence"
	presence.public_visibility = false
	presence.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE
	presence.replication_config = SceneReplicationConfig.new()
	for peer_id: int in ready_peers:
		presence.set_visibility_for(peer_id, true)
	actor.add_child(presence)
	actors[id] = actor
	actor.ready.connect(_track_actor.bind(actor))
	actor.tree_exiting.connect(_actor_removed.bind(id))
	return actor


func _track_actor(actor: Player) -> void:
	snapshots.track(actor)
	lag_compensator.track(actor)
	actor.equipment.combat.lag_compensator = lag_compensator
	actor.equipment.combat.interpolation_seconds = loader.current_data.snapshot_config.interpolation_seconds
	respawns.track(actor)
	combat_events.track(actor)


func respawn_pose(id: int) -> Transform3D:
	var pose: Transform3D = loader.spawn_pose
	pose.origin += pose.basis * loader.current_data.spawn_offset(_slots[id])
	return pose


func _actor_removed(id: int) -> void:
	combat_events.untrack(actors[id])
	respawns.untrack(actors[id])
	lag_compensator.untrack(actors[id])
	snapshots.untrack(actors[id])
	actors.erase(id)
	_slots.erase(id)


func _peer_left(id: int) -> void:
	ready_peers.erase(id)
	if multiplayer.is_server() and actors.has(id):
		actors[id].queue_free()


func clear() -> void:
	lag_compensator.clear()
	snapshots.reset()
	ready_peers.clear()
	_slots.clear()
	for actor: Player in actors.values():
		_container.remove_child(actor)
		actor.queue_free()
	actors.clear()
