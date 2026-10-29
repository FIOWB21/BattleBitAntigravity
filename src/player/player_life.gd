# Авторитетный жизненный цикл. HealthComponent.died означает потерю боеспособности.
class_name PlayerLife
extends Node

signal state_changed(state: State)
signal bleedout_changed(seconds: float)
signal finally_died(killer_id: int)

enum State { ALIVE, DOWNED, DEAD, SPAWN_SELECT }

const TIME_EPSILON: float = 0.00001

@export var rules: MatchRules = preload("res://src/core/default_match_rules.tres")

var state: State = State.ALIVE
var bleedout_remaining: float = 0.0
var reviver: ReviveInteractor
var interaction: ReviveInteractor
var view: PlayerLifeView
var network_respawn_managed: bool = false
var _player: Player
var _health: HealthComponent
var _killer: int = 0
var _spawn: Transform3D
var _neutral: PlayerInput = PlayerInput.new()


func setup(player: Player) -> void:
	_player = player
	_health = player.health_component as HealthComponent
	_spawn = player.global_transform
	_health.died.connect(_on_incapacitated)
	_health.finished_off.connect(_finish_death)
	_health.restored.connect(_on_restored)
	interaction = ReviveInteractor.new()
	add_child(interaction)
	interaction.setup(player)
	if player.is_local_player and not Game.is_dedicated:
		view = PlayerLifeView.new()
		add_child(view)
		view.setup(self)


func _physics_process(delta: float) -> void:
	step(delta)


func _exit_tree() -> void:
	_cancel_reviver()


func step(delta: float) -> void:
	if not _has_authority() or state != State.DOWNED or not is_finite(delta) or delta <= 0.0:
		return
	bleedout_remaining = maxf(0.0, bleedout_remaining - delta)
	bleedout_changed.emit(bleedout_remaining)
	if bleedout_remaining <= TIME_EPSILON:
		_finish_death(_killer)


func filter_input(inp: PlayerInput) -> PlayerInput:
	if state == State.ALIVE:
		return inp
	_neutral.tick = inp.tick
	_neutral.yaw = _player.rotation.y
	_neutral.pitch = inp.pitch
	_neutral.buttons = PlayerInput.BTN_PRONE
	_player.velocity.x = 0.0
	_player.velocity.z = 0.0
	return _neutral


func revive() -> bool:
	if not _has_authority() or state != State.DOWNED:
		return false
	return _health.restore_fraction(rules.revive_health_fraction)


# Начальная точка текущего полигона сохраняет прежнее поведение.
func select_initial_spawn() -> void:
	spawn_at(_spawn)


func select_beacon_spawn() -> bool:
	if not _has_authority() or state != State.SPAWN_SELECT:
		return false
	for node: Node in get_tree().get_nodes_in_group(SpawnBeacon.ACTIVE_GROUP):
		var beacon: SpawnBeacon = node as SpawnBeacon
		if beacon != null and beacon.try_spawn(_player):
			return true
	return false


func spawn_at(pose: Transform3D, service_spawn: bool = false) -> bool:
	if not _has_authority() or state != State.SPAWN_SELECT:
		return false
	if network_respawn_managed and not service_spawn:
		return false
	if not pose.is_finite():
		return false
	_player.global_transform = pose
	_player.velocity = Vector3.ZERO
	_player.input_reader.yaw = pose.basis.get_euler().y
	_player.input_reader.pitch = 0.0
	_player.head.rotation.x = 0.0
	_player.reset_physics_interpolation()
	_health.reset()
	if _player.is_local_player:
		_player.capture_mouse()
	return true


func sync_replica(value: State, health: float, maximum: float, bleedout: float) -> void:
	if not is_inside_tree() or multiplayer.is_server():
		return
	_health.max_health = maximum
	_health.current = health
	_health.is_dead = value != State.ALIVE
	_health.is_downed = value == State.DOWNED
	bleedout_remaining = bleedout
	_player.movement.blocked = value != State.ALIVE
	_health.health_changed.emit(health, maximum)
	if state != value:
		_set_state(value)
	bleedout_changed.emit(bleedout)


func _on_incapacitated(killer_id: int) -> void:
	if not _has_authority() or state != State.ALIVE:
		return
	_killer = killer_id
	if rules == null or not rules.is_valid() or not rules.downed_enabled:
		_finish_death(killer_id)
		return
	_health.is_downed = true
	bleedout_remaining = rules.bleedout_time
	_player.stance = PlayerStance.PRONE
	_set_state(State.DOWNED)
	bleedout_changed.emit(bleedout_remaining)


func _finish_death(killer_id: int) -> void:
	if not _has_authority() or state == State.DEAD or state == State.SPAWN_SELECT:
		return
	_health.is_downed = false
	_cancel_reviver()
	bleedout_remaining = 0.0
	_set_state(State.DEAD)
	finally_died.emit(killer_id)
	_set_state(State.SPAWN_SELECT)
	if _player.is_local_player:
		_player.release_mouse()


func _on_restored() -> void:
	if not _has_authority():
		return
	_cancel_reviver()
	bleedout_remaining = 0.0
	_set_state(State.ALIVE)
	var sc: StanceController = _player.stance_controller
	var restored_stance: int = PlayerStance.PRONE
	if sc.can_stand_to(PlayerStance.STAND):
		restored_stance = PlayerStance.STAND
	elif sc.can_stand_to(PlayerStance.CROUCH):
		restored_stance = PlayerStance.CROUCH
	_player.stance = restored_stance


func _cancel_reviver() -> void:
	if is_instance_valid(reviver):
		reviver.cancel()
	reviver = null


func _set_state(value: State) -> void:
	state = value
	state_changed.emit(state)


func _has_authority() -> bool:
	return is_inside_tree() and Game.is_server_or_offline(multiplayer)
