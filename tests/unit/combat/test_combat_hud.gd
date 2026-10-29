extends GutTest


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func test_killfeed_is_bounded_and_preserves_captured_names_weapon_and_headshot() -> void:
	var feed: KillFeed = KillFeed.new()
	for index: int in range(100):
		feed.record("Victim%d" % index, "Killer", &"sample_ar", index % 2 == 0)
	assert_eq(feed.lines.size(), feed.capacity)
	assert_true(feed.lines[0].ends_with("Victim94"))
	assert_true(feed.lines[0].contains("sample_ar / HEAD"))
	assert_false(feed.lines[5].contains("HEAD"))
	feed.record("Victim", "Environment", &"", false)
	assert_true(feed.lines[5].contains("environment"))


func test_events_update_ui_expire_and_reuse_all_controls() -> void:
	var ui: CombatHUD = CombatHUD.new()
	add_child_autofree(ui)
	ui.setup(null)
	ui.set_process(false)
	assert_gte(ui.feed_labels[0].get_global_rect().position.x, 0.0)
	assert_gte(ui.hit_label.get_global_rect().position.x, 0.0)
	var nodes: int = get_tree().get_node_count()
	Events.hit_confirmed.emit(HitboxZone.HEAD, false)
	assert_eq(ui.hit_label.text, "HEAD HIT")
	Events.hit_confirmed.emit(HitboxZone.TORSO, true)
	assert_eq(ui.hit_label.text, "KILL CONFIRMED")
	Events.damage_indicated.emit(Vector3.FORWARD)
	assert_true(ui.damage_label.visible)
	for index: int in range(100):
		Events.player_died.emit(42, 1, &"sample_ar", true)
	assert_eq(ui.feed.lines.size(), ui.feed.capacity)
	assert_eq(get_tree().get_node_count(), nodes)
	ui.advance(ui.feed_seconds + 1.0)
	assert_false(ui.hit_label.visible)
	assert_false(ui.damage_label.visible)
	for label: Label in ui.feed_labels:
		assert_false(label.visible)
