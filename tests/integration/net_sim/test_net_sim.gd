extends GutTest


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func test_enet_outgoing_jitter_loss_duplicates_and_reordering_keep_authority() -> void:
	var scenario: NetMatrixCase = NetMatrixCase.new()
	var result: Dictionary = await scenario.run(get_tree(), 100, 5.0, 20, 10.0, 10.0)
	assert_true(NetMatrixCase.valid_result(result), JSON.stringify(result))
	if not bool(result.get("ok", false)):
		return
	var client: Dictionary = result["client"]
	var server: Dictionary = result["server"]
	assert_gt(int(client["input_drops"]), 0)
	assert_gt(int(server["snapshot_drops"]), 0, "Downstream loss occurs before sending on server")
	assert_gt(int(client["input_duplicates"]), 0)
	assert_gt(int(server["snapshot_duplicates"]), 0)
	assert_gt(int(client["input_reorders"]), 0)
	assert_gt(int(server["snapshot_reorders"]), 0)
	print("NET SIM METRIC ", JSON.stringify(result))
