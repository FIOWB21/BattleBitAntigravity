extends GutTest

var _patient: Player
var _medic: Player


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _player(position: Vector3) -> Player:
	var player: Player = load("res://src/player/player.tscn").instantiate() as Player
	player.is_local_player = false
	player.position = position
	add_child_autofree(player)
	_freeze(player)
	return player


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_freeze(child)


func _setup() -> void:
	_patient = _player(Vector3(3200, 10, 3200))
	_medic = _player(_patient.position + Vector3(0, 0, 1.5))
	_medic.class_data = load("res://src/classes/data/medic.tres") as ClassData
	_patient.health_component.apply_damage(100.0)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _command(tick: int, held: bool = true) -> PlayerInput:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = tick
	inp.buttons = PlayerInput.BTN_INTERACT if held else 0
	var offset: Vector3 = _patient.head.global_position - _medic.head.global_position
	inp.pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
	inp.yaw = atan2(-offset.x, -offset.z)
	return inp


func _hold(first: int, last: int) -> void:
	for tick: int in range(first, last + 1):
		_medic.life.interaction.simulate(_command(tick), 1.0 / 60.0)


func test_interact_is_held_input_and_releases_without_buffering() -> void:
	var reader: LocalInputReader = LocalInputReader.new()
	Input.action_press(InputActions.INTERACT)
	assert_true(reader.read_input().pressed(PlayerInput.BTN_INTERACT))
	assert_true(reader.read_input().pressed(PlayerInput.BTN_INTERACT))
	Input.action_release(InputActions.INTERACT)
	assert_false(reader.read_input().pressed(PlayerInput.BTN_INTERACT))


func test_real_hitbox_target_revives_at_exact_three_second_boundary() -> void:
	await _setup()
	_hold(0, 179)
	assert_eq(_medic.life.interaction.target, _patient.life)
	assert_eq(_patient.life.state, PlayerLife.State.DOWNED)
	assert_almost_eq(_medic.life.interaction.progress, 179.0 / 180.0, 0.0001)
	_hold(180, 180)
	assert_eq(_patient.life.state, PlayerLife.State.ALIVE)
	assert_eq(_patient.health_component.current, 30.0)
	assert_null(_patient.life.reviver)
	assert_null(_medic.life.interaction.target)
	assert_eq(_medic.life.interaction.progress, 0.0)


func test_release_cancels_progress_and_next_hold_starts_over() -> void:
	await _setup()
	_hold(0, 100)
	_medic.life.interaction.simulate(_command(101, false), 1.0 / 60.0)
	assert_null(_medic.life.interaction.target)
	assert_null(_patient.life.reviver)
	_hold(102, 281)
	assert_eq(_patient.life.state, PlayerLife.State.DOWNED)
	_hold(282, 282)
	assert_eq(_patient.life.state, PlayerLife.State.ALIVE)


func test_walking_away_cancels_and_returning_does_not_keep_progress() -> void:
	await _setup()
	_hold(0, 90)
	_medic.position.z += 3.0
	_medic.life.interaction.simulate(_command(91), 1.0 / 60.0)
	assert_null(_medic.life.interaction.target)
	assert_eq(_medic.life.interaction.progress, 0.0)
	assert_null(_patient.life.reviver)
	_medic.position.z -= 3.0
	_hold(92, 182)
	assert_eq(_patient.life.state, PlayerLife.State.DOWNED)
	assert_almost_eq(_medic.life.interaction.progress, 0.5, 0.0001)


func test_medic_incapacitation_cancels_immediately_without_more_command() -> void:
	await _setup()
	_hold(0, 100)
	assert_eq(_patient.life.reviver, _medic.life.interaction)
	_medic.health_component.apply_damage(100.0)
	assert_null(_medic.life.interaction.target)
	assert_null(_patient.life.reviver)
	assert_eq(_medic.life.interaction.progress, 0.0)
	_hold(101, 500)
	assert_eq(_patient.life.state, PlayerLife.State.DOWNED)


func test_non_medic_and_looking_away_cannot_revive() -> void:
	await _setup()
	_medic.class_data = load("res://src/classes/data/assault.tres") as ClassData
	_hold(0, 200)
	assert_null(_medic.life.interaction.target)
	_medic.class_data = load("res://src/classes/data/medic.tres") as ClassData
	_hold(201, 290)
	var inp: PlayerInput = _command(291)
	inp.yaw += PI
	_medic.life.interaction.simulate(inp, 1.0 / 60.0)
	assert_null(_medic.life.interaction.target)
	assert_eq(_patient.life.state, PlayerLife.State.DOWNED)


func test_duplicates_old_ticks_and_missing_ticks_do_not_complete_hold() -> void:
	await _setup()
	_hold(0, 60)
	for repeat: int in range(200):
		_medic.life.interaction.simulate(_command(60), 1.0 / 60.0)
		_medic.life.interaction.simulate(_command(10), 1.0 / 60.0)
	assert_almost_eq(_medic.life.interaction.progress, 1.0 / 3.0, 0.0001)
	_hold(500, 679)
	assert_eq(_patient.life.state, PlayerLife.State.DOWNED)
	_hold(680, 680)
	assert_eq(_patient.health_component.current, 30.0)


func test_patient_finished_off_or_bled_out_cancels_immediately() -> void:
	await _setup()
	_hold(0, 100)
	_patient.life.step(20.0)
	assert_null(_medic.life.interaction.target)
	assert_null(_patient.life.reviver)
	assert_eq(_medic.life.interaction.progress, 0.0)
	_patient.health_component.reset()
	_patient.health_component.apply_damage(100.0)
	await get_tree().physics_frame
	_hold(101, 150)
	assert_not_null(_medic.life.interaction.target)
	_patient.health_component.apply_damage(1.0)
	assert_null(_medic.life.interaction.target)


func test_wall_blocks_selection_and_cancels_existing_hold() -> void:
	await _setup()
	_hold(0, 50)
	var wall: StaticBody3D = StaticBody3D.new()
	wall.position = _patient.position + Vector3(0, 1, 0.75)
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(3, 3, 0.1)
	col.shape = shape
	wall.add_child(col)
	add_child_autofree(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_medic.life.interaction.simulate(_command(51), 1.0 / 60.0)
	assert_null(_medic.life.interaction.target)
	assert_null(_patient.life.reviver)


func test_two_medics_cannot_combine_progress_and_removal_releases_target() -> void:
	await _setup()
	_hold(0, 70)
	var other: Player = _player(_medic.position)
	other.class_data = _medic.class_data
	other.life.interaction.simulate(_command(0), 1.0 / 60.0)
	assert_null(other.life.interaction.target)
	assert_eq(_patient.life.reviver, _medic.life.interaction)
	_medic.get_parent().remove_child(_medic)
	_medic = other
	assert_null(_patient.life.reviver)
	other.life.interaction.simulate(_command(1), 1.0 / 60.0)
	assert_eq(other.life.interaction.target, _patient.life)
	assert_eq(other.life.interaction.progress, 0.0)
