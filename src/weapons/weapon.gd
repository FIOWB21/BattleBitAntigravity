# Серверный автомат оружия: один вызов simulate на тик, без ввода ОС и представления.
class_name Weapon
extends Node3D

signal fired(tick: int)
signal reload_started
signal reload_finished
signal ammo_changed(magazine: int, reserve: int)
signal configured
signal stats_changed
signal dry_fired(tick: int)
signal reload_cancelled

enum State { IDLE, FIRING, RELOADING, SWITCHING_IN, SWITCHING_OUT, BLOCKED }

@export var data: WeaponData
@export var ticks_per_second: int = Engine.physics_ticks_per_second

var state: State = State.IDLE
var fire_mode: WeaponData.FireMode = WeaponData.FireMode.SEMI
var ammo_in_mag: int = 0
var reserve_ammo: int = 0
var next_fire_tick: int = 0
var reload_end_tick: int = -1
var switch_end_tick: int = -1
var attachments: WeaponAttachments = WeaponAttachments.new()

var _last_tick: int = -1
var _fire_held: bool = false
var _reload_held: bool = false
var _burst_remaining: int = 0
var _equipped: bool = true
var _reload_capacity: int = 0


func _ready() -> void:
	if data != null:
		setup(data)


func setup(weapon_data: WeaponData) -> void:
	data = weapon_data
	attachments.setup(self, weapon_data)
	state = State.IDLE
	fire_mode = data.fire_modes[0] if not data.fire_modes.is_empty() else WeaponData.FireMode.SEMI
	ammo_in_mag = maxi(data.mag_size, 0)
	reserve_ammo = reserve_capacity()
	next_fire_tick = 0
	reload_end_tick = -1
	switch_end_tick = -1
	_last_tick = -1
	_fire_held = false
	_reload_held = false
	_burst_remaining = 0
	_equipped = true
	_reload_capacity = 0
	ammo_changed.emit(ammo_in_mag, reserve_ammo)
	configured.emit()


# blocked передаётся симуляцией движения: спринт, лестница или падение.
func simulate(inp: PlayerInput, blocked: bool = false, sprinting: bool = false) -> void:
	if not _has_authority() or inp.tick <= _last_tick:
		return
	_simulate(inp, blocked, sprinting)


# Client replicas run the same timers for presentation only.
func simulate_cosmetic(inp: PlayerInput, blocked: bool, sprinting: bool) -> void:
	if not is_inside_tree() or multiplayer.is_server() or data == null or inp.tick <= _last_tick:
		return
	_simulate(inp, blocked, sprinting)


func _simulate(inp: PlayerInput, blocked: bool, sprinting: bool) -> void:
	_last_tick = inp.tick
	var fire_pressed: bool = inp.pressed(PlayerInput.BTN_FIRE) and not _fire_held
	var reload_pressed: bool = inp.pressed(PlayerInput.BTN_RELOAD) and not _reload_held
	_fire_held = inp.pressed(PlayerInput.BTN_FIRE)
	_reload_held = inp.pressed(PlayerInput.BTN_RELOAD)
	if state == State.RELOADING and sprinting and data.reload_interrupt_on_sprint:
		_cancel_reload()
	_advance_state()
	match state:
		State.RELOADING, State.SWITCHING_IN, State.SWITCHING_OUT:
			return
	if blocked or sprinting or not _equipped:
		state = State.BLOCKED
		_burst_remaining = 0
		return
	if state == State.BLOCKED:
		state = State.IDLE
	if reload_pressed and _start_reload():
		return
	_try_fire(fire_pressed)


func cycle_fire_mode() -> bool:
	if not _has_authority() or (state != State.IDLE and state != State.FIRING):
		return false
	if data.fire_modes.size() < 2:
		return false
	var index: int = data.fire_modes.find(fire_mode)
	fire_mode = data.fire_modes[(index + 1) % data.fire_modes.size()]
	_burst_remaining = 0
	return true


# Команды смены используют последний обработанный тик той же симуляции.
func switch_out() -> bool:
	if not _has_authority() or _last_tick < 0 or not _equipped:
		return false
	if state == State.SWITCHING_IN or state == State.SWITCHING_OUT:
		return false
	if state == State.RELOADING:
		if not data.reload_interrupt_on_switch:
			return false
		_cancel_reload()
	state = State.SWITCHING_OUT
	switch_end_tick = _last_tick + _duration_ticks(data.draw_time)
	reload_end_tick = -1
	_burst_remaining = 0
	return true


func switch_in() -> bool:
	if not _has_authority() or _last_tick < 0 or _equipped or state != State.BLOCKED:
		return false
	state = State.SWITCHING_IN
	switch_end_tick = _last_tick + _duration_ticks(data.draw_time)
	return true


# Только начальная раскладка инвентаря; боезапас не переинициализируется.
func holster() -> void:
	if not _has_authority() or _last_tick >= 0:
		return
	_equipped = false
	state = State.BLOCKED
	_burst_remaining = 0


func equip_initial() -> void:
	if not _has_authority() or _last_tick >= 0:
		return
	_equipped = true
	state = State.IDLE


# Завершает только срок смены, сохраняя возможность обработать ввод этого же тика.
func advance_switch(tick: int) -> void:
	if not _has_authority() or tick <= _last_tick:
		return
	if state != State.SWITCHING_IN and state != State.SWITCHING_OUT:
		return
	if tick >= switch_end_tick:
		_finish_switch()


func _has_authority() -> bool:
	return data != null and is_inside_tree() and multiplayer.is_server()


func _duration_ticks(seconds: float) -> int:
	return maxi(1, ceili(maxf(seconds, 0.0) * maxi(ticks_per_second, 1)))


func _advance_state() -> void:
	match state:
		State.FIRING:
			if _last_tick >= next_fire_tick:
				state = State.IDLE
		State.RELOADING:
			if _last_tick >= reload_end_tick:
				_finish_reload()
		State.SWITCHING_IN, State.SWITCHING_OUT:
			if _last_tick >= switch_end_tick:
				_finish_switch()


func _finish_switch() -> void:
	_equipped = state == State.SWITCHING_IN
	state = State.IDLE if _equipped else State.BLOCKED
	switch_end_tick = -1


func _start_reload() -> bool:
	_reload_capacity = maxi(data.mag_size, 0)
	if data.chamber_enabled and ammo_in_mag > 0 and _reload_capacity > 0:
		_reload_capacity += 1
	if ammo_in_mag >= _reload_capacity or reserve_ammo <= 0:
		return false
	var duration: float = data.reload_empty_time if ammo_in_mag == 0 else data.reload_time
	reload_end_tick = _last_tick + _duration_ticks(duration)
	state = State.RELOADING
	_burst_remaining = 0
	reload_started.emit()
	return true


func _finish_reload() -> void:
	var transferred: int = mini(maxi(_reload_capacity - ammo_in_mag, 0), reserve_ammo)
	ammo_in_mag += transferred
	reserve_ammo -= transferred
	reload_end_tick = -1
	state = State.IDLE
	ammo_changed.emit(ammo_in_mag, reserve_ammo)
	reload_finished.emit()


func _cancel_reload() -> void:
	reload_end_tick = -1
	state = State.IDLE
	_burst_remaining = 0
	reload_cancelled.emit()


func reserve_capacity() -> int:
	return maxi(data.mag_size, 0) * maxi(data.reserve_mags, 0) if data != null else 0


func add_reserve_ammo(amount: int) -> int:
	if not _has_authority() or amount <= 0:
		return 0
	var added: int = mini(amount, maxi(reserve_capacity() - reserve_ammo, 0))
	if added > 0:
		reserve_ammo += added
		ammo_changed.emit(ammo_in_mag, reserve_ammo)
	return added


func _try_fire(fire_pressed: bool) -> void:
	if _last_tick < next_fire_tick or data.rpm <= 0.0:
		return
	var wants_fire: bool = false
	match fire_mode:
		WeaponData.FireMode.SEMI:
			wants_fire = fire_pressed
		WeaponData.FireMode.AUTO:
			wants_fire = _fire_held
		WeaponData.FireMode.BURST:
			if fire_pressed and _burst_remaining == 0:
				_burst_remaining = maxi(data.burst_count, 1)
			wants_fire = _burst_remaining > 0
	if not wants_fire:
		return
	if ammo_in_mag <= 0:
		_burst_remaining = 0
		if fire_pressed:
			dry_fired.emit(_last_tick)
		return
	if fire_mode == WeaponData.FireMode.BURST:
		_burst_remaining -= 1
	_discharge()


func fire_requested(tick: int) -> bool:
	if not _has_authority() or tick != _last_tick or tick < next_fire_tick:
		return false
	if not _equipped or ammo_in_mag <= 0 or data.rpm <= 0.0:
		return false
	if state != State.IDLE and state != State.FIRING:
		return false
	_discharge()
	return true


func _discharge() -> void:
	ammo_in_mag -= 1
	next_fire_tick = _last_tick + _duration_ticks(data.cooldown())
	state = State.FIRING
	if multiplayer.is_server():
		ammo_changed.emit(ammo_in_mag, reserve_ammo)
	fired.emit(_last_tick)


func sync_replica(state_value: State, tick: int, cooldown: int, reload_ticks: int, switch_ticks: int) -> void:
	if not is_inside_tree() or multiplayer.is_server():
		return
	state = state_value
	_equipped = state != State.BLOCKED and state != State.SWITCHING_IN
	next_fire_tick = maxi(next_fire_tick, tick + cooldown)
	reload_end_tick = tick + reload_ticks if state == State.RELOADING else -1
	switch_end_tick = tick + switch_ticks if state == State.SWITCHING_IN or state == State.SWITCHING_OUT else -1
