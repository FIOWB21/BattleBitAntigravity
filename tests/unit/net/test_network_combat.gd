extends GutTest

var _actor: Player
var _combat: NetworkCombat
var _input: PlayerInput
var _aim: Transform3D
var _previous_tick: int


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_previous_tick = Net.tick
	_actor = preload("res://src/player/player.tscn").instantiate() as Player
	_actor.network_owner_id = 42
	_actor.position = Vector3(500.0, 20.0, 500.0)
	add_child_autofree(_actor)
	_actor.set_physics_process(false)
	_combat = _actor.equipment.combat
	_input = PlayerInput.new()
	_aim = Transform3D(Basis.IDENTITY, _actor.head.global_position)


func after_each() -> void:
	Net.tick = _previous_tick


func _step(server_tick: int, input_tick: int, blocked: bool = false) -> void:
	Net.tick = server_tick
	_input.tick = server_tick
	_actor.server_sim.input_queue.last_input_tick = input_tick
	_combat.simulate(_input, _aim, blocked)
	_combat._resolve(blocked)


func test_raw_fire_input_cannot_shoot_without_explicit_request() -> void:
	var ammo: int = _actor.weapon.ammo_in_mag
	_input.buttons = PlayerInput.BTN_FIRE
	for tick: int in range(100, 160):
		_step(tick, tick + 5)
	assert_eq(_actor.weapon.ammo_in_mag, ammo)
	assert_eq(_combat.accepted_shots, 0)


func test_request_waits_for_its_input_and_uses_recorded_server_aim() -> void:
	var seed: int = FireHistory.shot_seed(105, 42)
	assert_true(_combat.history.request(105, seed, 42, 100))
	_step(100, 104)
	assert_eq(_combat.accepted_shots, 0)
	_step(101, 105)
	assert_eq(_combat.accepted_shots, 1)
	assert_eq(_combat.history.slot(105).aim.origin, _aim.origin)
	assert_false(_combat.history.request(105, seed, 42, 101))


func test_late_request_keeps_authoritative_aim_for_requested_input_tick() -> void:
	_step(100, 105)
	var recorded: Transform3D = _combat.history.slot(105).aim
	_aim = Transform3D(Basis(Vector3.UP, PI), Vector3(900.0, 50.0, 900.0))
	assert_true(_combat.history.request(105, FireHistory.shot_seed(105, 42), 42, 101))
	_step(101, 106)
	assert_eq(_combat.accepted_shots, 1)
	assert_eq(_actor.weapon_hitscan.aim_transform, recorded)
	assert_ne(_actor.weapon_hitscan.aim_transform, _aim)


func test_stale_blocked_context_cannot_become_valid_after_unblocking() -> void:
	_step(100, 105, true)
	assert_true(_combat.history.request(105, FireHistory.shot_seed(105, 42), 42, 101))
	_step(101, 106)
	assert_eq(_combat.accepted_shots, 0)
	assert_eq(_combat.rejected_requests, 1)


func test_requests_without_consumed_input_do_not_create_shots() -> void:
	for tick: int in range(105, 120):
		assert_true(_combat.history.request(tick, FireHistory.shot_seed(tick, 42), 42, 100))
	_step(100, 104)
	assert_eq(_combat.accepted_shots, 0)
	assert_eq(_actor.weapon.ammo_in_mag, _actor.weapon.data.mag_size)


func test_unowned_rpc_and_client_entry_on_server_are_ignored() -> void:
	Net.tick = 100
	_combat.fire(105, FireHistory.shot_seed(105, 42), 94)
	assert_eq(_combat.rejected_requests, 1)
	assert_null(_combat.history.take_ready(100))
	_input.tick = 105
	_input.buttons = PlayerInput.BTN_FIRE
	_combat.predict(_input)
	assert_eq(_combat.sent_requests, 0)
	assert_eq(_actor.weapon.ammo_in_mag, _actor.weapon.data.mag_size)
