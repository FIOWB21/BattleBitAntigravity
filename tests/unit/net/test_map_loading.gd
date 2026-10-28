extends GutTest

var _loader: MapLoader


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_loader = MapLoader.new()
	add_child(_loader)


func after_each() -> void:
	Net.disconnect_all()
	_loader.free()
	Game.map_id = "testbed"
	await get_tree().process_frame


func test_map_catalog_and_offline_removal_preserve_spawn_and_geometry() -> void:
	assert_eq(_loader.load_map("testbed"), OK)
	assert_true(Game.is_in_game())
	assert_not_null(_loader.current_map.get_node_or_null("Floor"))
	assert_not_null(_loader.current_map.get_node_or_null("PlayerSpawn"))
	for path: NodePath in _loader.current_data.offline_paths:
		assert_null(_loader.current_map.get_node_or_null(path))
	assert_eq(_loader.spawn_pose.origin, Vector3(0.0, 0.1, 10.0))
	var original: Node3D = _loader.current_map
	assert_eq(_loader.load_map("testbed"), OK)
	assert_eq(_loader.current_map, original)
	assert_true(_loader.players.actors.is_empty())


func test_unknown_map_fails_without_loading_or_entering_game() -> void:
	Game.set_state(Game.State.MENU)
	for id: String in ["", "../testbed", "missing_map"]:
		assert_eq(_loader.load_map(id), ERR_DOES_NOT_EXIST)
		assert_null(_loader.current_map)
		assert_true(Game.is_in_menu())


func test_missing_spawn_and_invalid_layout_are_rejected() -> void:
	var data: MapData = _loader.maps[0].duplicate() as MapData
	_loader.maps = [data]
	data.spawn_path = ^"MissingSpawn"
	assert_eq(_loader.load_map("testbed"), ERR_INVALID_DATA)
	assert_null(_loader.current_map)
	data.spawn_columns = 0
	assert_eq(_loader.load_map("testbed"), ERR_DOES_NOT_EXIST)
	data.spawn_columns = 3
	for invalid: float in [0.0, -1.0, NAN, INF]:
		data.spawn_spacing = invalid
		assert_eq(_loader.load_map("testbed"), ERR_DOES_NOT_EXIST)
		data.spawn_spacing = 2.0
		data.spawn_row_spacing = invalid
		assert_eq(_loader.load_map("testbed"), ERR_DOES_NOT_EXIST)
		data.spawn_row_spacing = 4.0


func test_spawn_layout_starts_at_marker_and_never_overlaps_32_players() -> void:
	var data: MapData = _loader.maps[0]
	assert_eq(data.spawn_offset(0), Vector3.ZERO)
	for first: int in range(32):
		for second: int in range(first):
			assert_gt(data.spawn_offset(first).distance_to(data.spawn_offset(second)), 0.7)


func test_disconnect_unloads_world_and_restores_menu_repeatedly() -> void:
	for attempt: int in range(3):
		assert_eq(_loader.load_map("testbed"), OK)
		Net.disconnect_all()
		assert_null(_loader.current_map)
		assert_true(_loader.players.actors.is_empty())
		assert_true(Game.is_in_menu())
		assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE)
		await get_tree().process_frame


func test_local_call_to_ready_cannot_spawn_offline_or_unadmitted_player() -> void:
	assert_eq(_loader.load_map("testbed"), OK)
	_loader.players.map_ready("testbed")
	_loader.players.map_ready("forged_map")
	assert_true(_loader.players.actors.is_empty())
