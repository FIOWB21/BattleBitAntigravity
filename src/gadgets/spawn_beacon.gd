# Собственный разрушаемый гаджет; команда и отряд фиксируются сервером при деплое.
class_name SpawnBeacon
extends Deployable

signal player_spawned(player: Player)

const ACTIVE_GROUP: StringName = &"active_spawn_beacons"

@export var config: BeaconConfig

var _query: BeaconSpawnQuery = BeaconSpawnQuery.new()

@onready var health: HealthComponent = $Health
@onready var _zone: HitboxZone = $Zone


func _ready() -> void:
	if config == null or not config.is_valid():
		return
	health.max_health = config.max_health
	health.died.connect(_on_destroyed)
	if not Game.is_server_or_offline(multiplayer):
		return
	health.reset()
	for node: Node in get_tree().get_nodes_in_group(ACTIVE_GROUP):
		var previous: SpawnBeacon = node as SpawnBeacon
		if previous != null and previous.get_parent() == get_parent() \
				and owner_id > 0 and previous.owner_id == owner_id:
			previous.despawn()
	add_to_group(ACTIVE_GROUP)


func can_spawn(player: Player) -> bool:
	return not _despawned and config != null and config.is_valid() \
		and is_instance_valid(player) and player.is_inside_tree() and is_inside_tree() \
		and Game.is_server_or_offline(multiplayer) and Game.is_server_or_offline(player.multiplayer) \
		and not health.is_dead and get_parent() == player.get_parent() \
		and player.life != null and player.life.state == PlayerLife.State.SPAWN_SELECT \
		and team_id > 0 and team_id == player.affiliation.team_id \
		and squad_id > 0 and squad_id == player.affiliation.squad_id


func try_spawn(player: Player) -> bool:
	if not can_spawn(player) or not _query.solve(player, global_transform, config):
		return false
	if not player.life.spawn_at(_query.pose):
		return false
	player_spawned.emit(player)
	return true


func despawn() -> bool:
	if not super.despawn():
		return false
	visible = false
	_zone.collision_layer = 0
	return true


func _on_destroyed(_killer_id: int) -> void:
	despawn()
