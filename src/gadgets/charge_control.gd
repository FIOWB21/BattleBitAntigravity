# Реестр принадлежит компоненту игрока, а не автолоаду или клиентскому запросу.
class_name ChargeControl
extends Node

signal exploded(profile: ProjectileData, point: Vector3, attacker: int)

var _charges: Array[ExplosiveCharge] = []


func track(object: Deployable) -> void:
	var charge: ExplosiveCharge = object as ExplosiveCharge
	if charge == null:
		return
	var owned: int = 0
	var oldest: ExplosiveCharge
	for existing: ExplosiveCharge in _charges:
		if existing.owner_id == charge.owner_id:
			owned += 1
			if oldest == null:
				oldest = existing
	if owned >= charge.config.max_active:
		oldest.despawn()
	_charges.append(charge)
	charge.despawned.connect(_forget.bind(charge), CONNECT_ONE_SHOT)
	charge.tree_exiting.connect(_forget.bind(charge), CONNECT_ONE_SHOT)
	charge.detonated.connect(_on_detonated)


func detonate(owner: int) -> void:
	if not Game.is_server_or_offline(multiplayer):
		return
	# Удаление из реестра происходит синхронно сигналом despawned.
	for index: int in range(_charges.size() - 1, -1, -1):
		_charges[index].detonate(owner)


func _forget(charge: ExplosiveCharge) -> void:
	_charges.erase(charge)


func _on_detonated(profile: ProjectileData, point: Vector3, attacker: int) -> void:
	exploded.emit(profile, point, attacker)
