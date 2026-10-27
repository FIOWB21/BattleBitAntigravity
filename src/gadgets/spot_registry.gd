# Один локальный реестр на мир, без автолоада/RPC. Сроки изменяет только сервер.
class_name SpotRegistry
extends RefCounted

signal spotted(index: int)
signal expired(index: int)

var data: SpottingData = preload("res://src/gadgets/data/spotting_device.tres")

var marks: Array[SpotMark] = []
var _world: Node
var _last_frame: int = -1


func setup(world: Node) -> void:
	_world = world
	for index: int in range(data.capacity):
		marks.append(SpotMark.new())


static func for_world(world: Node) -> SpotRegistry:
	var registry: SpotRegistry
	if world.has_meta(&"spot_registry"):
		registry = world.get_meta(&"spot_registry") as SpotRegistry
	if registry == null:
		registry = SpotRegistry.new()
		registry.setup(world)
		world.set_meta(&"spot_registry", registry)
	return registry


func can_spot(target: CombatAffiliation, team: int) -> bool:
	if not _has_authority() or not is_instance_valid(target) \
			or not target.is_alive() or team <= 0 or target.team_id <= 0 or target.team_id == team:
		return false
	for mark: SpotMark in marks:
		if mark.remaining <= 0.0 or (mark.target == target and mark.team_id == team):
			return true
	return false


func spot(target: CombatAffiliation, team: int, duration: float) -> bool:
	if not is_finite(duration) or duration <= 0.0 or not can_spot(target, team):
		return false
	var available: int = -1
	for index: int in range(marks.size()):
		var mark: SpotMark = marks[index]
		if mark.target == target and mark.team_id == team and mark.remaining > 0.0:
			available = index
			break
		if available < 0 and mark.remaining <= 0.0:
			available = index
	var mark: SpotMark = marks[available]
	mark.target = target
	mark.team_id = team
	mark.remaining = duration
	spotted.emit(available)
	return true


func advance(delta: float, frame: int) -> void:
	if frame <= _last_frame or not _has_authority():
		return
	_last_frame = frame
	step(delta)


func step(delta: float) -> void:
	if not _has_authority() or not is_finite(delta) or delta <= 0.0:
		return
	for index: int in range(marks.size()):
		var mark: SpotMark = marks[index]
		if mark.remaining <= 0.0:
			continue
		mark.remaining = maxf(0.0, mark.remaining - delta)
		if mark.remaining <= PlayerLife.TIME_EPSILON or not mark.is_visible_to(mark.team_id):
			mark.remaining = 0.0
			mark.target = null
			expired.emit(index)


func _has_authority() -> bool:
	return is_instance_valid(_world) and _world.is_inside_tree() \
		and Game.is_server_or_offline(_world.multiplayer)
