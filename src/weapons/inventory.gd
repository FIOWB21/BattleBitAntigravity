# Серверный выбор слотов. Все экземпляры и вспомогательный ввод создаются при загрузке.
class_name Inventory
extends Node

signal active_slot_changed(slot: int, weapon: Weapon)
signal switch_started(from_slot: int, to_slot: int)
signal switch_finished(slot: int)

enum Phase { READY, HOLSTERING, DRAWING }

@export var loadout: Loadout
@export var primary_weapon: Weapon

var active_slot: int = Loadout.Slot.NONE
var last_weapon_slot: int = Loadout.Slot.NONE
var phase: Phase = Phase.READY
var end_tick: int = -1

var _weapons: Array[Weapon] = []
var _pending_slot: int = Loadout.Slot.NONE
var _last_tick: int = -1
var _neutral: PlayerInput = PlayerInput.new()


func _ready() -> void:
	_weapons.resize(Loadout.SLOT_COUNT + 1)
	if loadout == null:
		return
	for slot: int in range(1, Loadout.SLOT_COUNT + 1):
		var data: WeaponData = loadout.item_at(slot) as WeaponData
		if data == null:
			continue
		var weapon: Weapon = primary_weapon if slot == Loadout.Slot.PRIMARY else null
		if weapon == null:
			weapon = Weapon.new()
			weapon.data = data
			var click: WeaponDryFire = WeaponDryFire.new()
			weapon.add_child(click)
			add_child(weapon)
		_weapons[slot] = weapon
		weapon.holster()
	active_slot = next_slot(Loadout.Slot.NONE, 1)
	var active: Weapon = active_weapon()
	if active != null:
		active.equip_initial()
	active_slot_changed.emit(active_slot, active)


func weapon_at(slot: int) -> Weapon:
	return _weapons[slot] if slot > 0 and slot < _weapons.size() else null


func active_weapon() -> Weapon:
	return weapon_at(active_slot)


func next_slot(from_slot: int, direction: int) -> int:
	if loadout == null or direction == 0:
		return from_slot
	var slot: int = from_slot
	for offset: int in range(Loadout.SLOT_COUNT):
		slot = wrapi(slot - 1 + signi(direction), 0, Loadout.SLOT_COUNT) + 1
		if loadout.item_at(slot) != null:
			return slot
	return Loadout.Slot.NONE


# Вызывается перед симуляцией активного оружия: команда смены имеет приоритет над огнём.
func simulate(inp: PlayerInput, allowed: bool = true) -> void:
	if not is_inside_tree() or not multiplayer.is_server() or inp.tick <= _last_tick:
		return
	_last_tick = inp.tick
	_neutral.tick = inp.tick
	_neutral.buttons = 0
	for weapon: Weapon in _weapons:
		if weapon != null and weapon != active_weapon():
			weapon.simulate(_neutral, true)
	if phase == Phase.HOLSTERING and inp.tick >= end_tick:
		_begin_draw(inp)
	elif phase == Phase.DRAWING and inp.tick >= end_tick:
		var weapon: Weapon = active_weapon()
		if weapon != null:
			weapon.advance_switch(inp.tick)
		phase = Phase.READY
		end_tick = -1
		switch_finished.emit(active_slot)
	if phase != Phase.READY or not allowed:
		return
	var requested: int = inp.weapon_slot
	if requested == Loadout.Slot.NONE and inp.weapon_cycle != 0:
		requested = next_slot(active_slot, inp.weapon_cycle)
	if requested == Loadout.Slot.NONE and inp.last_weapon:
		requested = last_weapon_slot
	_request_slot(requested, inp)


func _request_slot(slot: int, inp: PlayerInput) -> void:
	if loadout == null or slot == active_slot or loadout.item_at(slot) == null:
		return
	var weapon: Weapon = active_weapon()
	if weapon != null:
		# Синхронизируем срок команды с этим тиком без выстрела/новой перезарядки.
		_neutral.buttons = inp.buttons & ~PlayerInput.BTN_RELOAD
		weapon.simulate(_neutral, true)
		if not weapon.switch_out():
			return
	_pending_slot = slot
	phase = Phase.HOLSTERING
	end_tick = inp.tick + _duration_ticks(loadout.draw_time_at(active_slot))
	if weapon != null:
		end_tick = weapon.switch_end_tick
	switch_started.emit(active_slot, slot)


func _begin_draw(inp: PlayerInput) -> void:
	var previous: Weapon = active_weapon()
	if previous != null:
		previous.simulate(inp, true)
		last_weapon_slot = active_slot
	active_slot = _pending_slot
	_pending_slot = Loadout.Slot.NONE
	phase = Phase.DRAWING
	end_tick = inp.tick + _duration_ticks(loadout.draw_time_at(active_slot))
	var weapon: Weapon = active_weapon()
	if weapon != null:
		weapon.switch_in()
		end_tick = weapon.switch_end_tick
	active_slot_changed.emit(active_slot, weapon)


func _duration_ticks(seconds: float) -> int:
	return maxi(1, ceili(maxf(seconds, 0.0) * Engine.physics_ticks_per_second))
