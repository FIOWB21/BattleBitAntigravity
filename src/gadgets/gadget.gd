# Серверный автомат. Вызывается симуляцией; не опрашивает Input и не использует Timer.
class_name Gadget
extends Node

signal used(ctx: GadgetContext)
signal charges_changed(charges: int)
signal reload_started(end_tick: int)
signal reload_finished
signal deployable_created(object: Deployable)

@export var data: GadgetData
@export var ticks_per_second: int = Engine.physics_ticks_per_second

var charges: int = 0
var next_use_tick: int = 0
var reload_end_tick: int = -1

var _last_tick: int = -1
var _last_action_tick: int = -1
var _configured: bool = false
var _using: bool = false


func _ready() -> void:
	if data != null:
		setup(data)


# Начальная настройка не может повторно выдать заряды работающему экземпляру.
func setup(profile: GadgetData) -> bool:
	if not _has_authority() or _configured or profile == null or not profile.is_valid():
		return false
	if ticks_per_second <= 0:
		return false
	data = profile
	charges = profile.max_charges
	_configured = true
	charges_changed.emit(charges)
	return true


func simulate(tick: int) -> void:
	if not _has_authority() or not _configured or tick <= _last_tick:
		return
	_last_tick = tick
	if reload_end_tick >= 0 and tick >= reload_end_tick:
		reload_end_tick = -1
		charges = data.max_charges
		charges_changed.emit(charges)
		reload_finished.emit()


func can_use() -> bool:
	return _has_authority() and _configured and not _using and _last_tick >= 0 \
		and _last_action_tick != _last_tick and charges > 0 and reload_end_tick < 0 \
		and _last_tick >= next_use_tick


func can_use_at(tick: int) -> bool:
	return tick == _last_tick and can_use()


func use(ctx: GadgetContext) -> bool:
	if ctx == null or ctx.tick < _last_tick:
		return false
	simulate(ctx.tick)
	if not can_use():
		return false
	_using = true
	var object: Deployable
	if data.deployable_scene != null:
		object = Deployable.spawn(data.deployable_scene, ctx)
		if object == null:
			_using = false
			return false
	charges -= 1
	_last_action_tick = _last_tick
	next_use_tick = _last_tick + _duration_ticks(data.cooldown)
	_using = false
	charges_changed.emit(charges)
	if object != null:
		deployable_created.emit(object)
	used.emit(ctx)
	return true


# Перезарядка восстанавливает полный набор; запас/снабжение конкретных классов не заданы.
func reload(tick: int) -> bool:
	if tick < _last_tick or _using:
		return false
	simulate(tick)
	if not _has_authority() or not _configured or tick < 0:
		return false
	if _last_action_tick == tick or reload_end_tick >= 0 or charges >= data.max_charges:
		return false
	_last_action_tick = tick
	reload_end_tick = tick + _duration_ticks(data.reload_time)
	reload_started.emit(reload_end_tick)
	return true


func _has_authority() -> bool:
	return is_inside_tree() and Game.is_server_or_offline(multiplayer)


func _duration_ticks(seconds: float) -> int:
	return maxi(1, ceili(seconds * ticks_per_second))


func reset_for_spawn() -> void:
	if not _has_authority() or not _configured:
		return
	charges = data.max_charges
	next_use_tick = 0
	reload_end_tick = -1
	charges_changed.emit(charges)
