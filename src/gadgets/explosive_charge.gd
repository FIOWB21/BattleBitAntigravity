# Мина реагирует только на технику; оба заряда принимают серверную команду владельца.
class_name ExplosiveCharge
extends Deployable

signal detonated(profile: ProjectileData, point: Vector3, attacker: int)

@export var config: ChargeConfig

var armed: bool = false
var _elapsed: float = 0.0
var _spent: bool = false
var _nearby: Dictionary[RepairSurface, bool] = {}

@onready var blast: ChargeBlast = $Blast
@onready var _trigger: Area3D = $Trigger
@onready var _collision: CollisionShape3D = $Trigger/CollisionShape3D


func _ready() -> void:
	if config == null or not config.is_valid():
		return
	_collision.shape = _collision.shape.duplicate()
	(_collision.shape as SphereShape3D).radius = config.trigger_radius
	_trigger.area_entered.connect(_on_entered)
	_trigger.area_exited.connect(_on_exited)


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if _spent or not Game.is_server_or_offline(multiplayer) or config == null or not config.is_valid():
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	_elapsed += delta
	armed = _elapsed + PlayerLife.TIME_EPSILON >= config.arming_time
	if not armed or not config.vehicle_trigger:
		return
	for surface: RepairSurface in _nearby:
		if is_instance_valid(surface) and is_instance_valid(surface.health) and not surface.health.is_dead:
			detonate(owner_id)
			return


func detonate(requester: int) -> bool:
	if _spent or _despawned or not armed or requester != owner_id \
			or not Game.is_server_or_offline(multiplayer):
		return false
	_spent = true
	var point: Vector3 = global_transform * config.blast_offset
	blast.apply(config, point, source_id)
	detonated.emit(config.blast, point, source_id)
	despawn()
	return true


func _on_entered(area: Area3D) -> void:
	if area is RepairSurface:
		_nearby[area as RepairSurface] = true


func _on_exited(area: Area3D) -> void:
	if area is RepairSurface:
		_nearby.erase(area)
