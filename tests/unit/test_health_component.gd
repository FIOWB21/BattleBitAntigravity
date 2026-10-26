extends GutTest

const PLAYER_SCENE_PATH: String = "res://src/player/player.tscn"


func test_initial_state_and_apply_damage_signals() -> void:
	var hc: HealthComponent = HealthComponent.new()
	add_child_autofree(hc)
	assert_almost_eq(hc.max_health, 100.0, 0.001, "Default max_health must be 100.0")
	assert_almost_eq(hc.current, 100.0, 0.001, "Initial current health must equal max_health")
	assert_false(hc.is_dead, "Component must not be dead initially")

	var damaged_events: Array[Dictionary] = []
	var health_events: Array[Vector2] = []
	hc.damaged.connect(func(amount: float, source_id: int, zone: int) -> void:
		damaged_events.append({"amount": amount, "source_id": source_id, "zone": zone})
	)
	hc.health_changed.connect(func(cur: float, max_val: float) -> void:
		health_events.append(Vector2(cur, max_val))
	)

	hc.apply_damage(0.0, 2, 1)
	hc.apply_damage(-15.0, 2, 1)
	assert_eq(damaged_events.size(), 0, "Zero or negative damage must be ignored")
	assert_almost_eq(hc.current, 100.0, 0.001, "Health must remain 100.0")

	hc.apply_damage(35.0, 7, 2)
	assert_almost_eq(hc.current, 65.0, 0.001, "Health must decrease to 65.0")
	assert_false(hc.is_dead, "Must still be alive at 65 HP")
	assert_eq(damaged_events.size(), 1, "damaged signal must emit once")
	assert_almost_eq(float(damaged_events[0]["amount"]), 35.0, 0.001)
	assert_eq(int(damaged_events[0]["source_id"]), 7)
	assert_eq(int(damaged_events[0]["zone"]), 2)
	assert_eq(health_events.size(), 1, "health_changed signal must emit once")
	assert_almost_eq(health_events[0].x, 65.0, 0.001)
	assert_almost_eq(health_events[0].y, 100.0, 0.001)


func test_death_emits_exactly_once_and_ignores_damage_when_dead() -> void:
	var hc: HealthComponent = HealthComponent.new()
	add_child_autofree(hc)
	var killers: Array[int] = []
	var damaged_amounts: Array[float] = []
	hc.died.connect(func(killer_id: int) -> void:
		killers.append(killer_id)
	)
	hc.damaged.connect(func(amount: float, _source_id: int, _zone: int) -> void:
		damaged_amounts.append(amount)
	)

	hc.apply_damage(60.0, 3, 0)
	assert_false(hc.is_dead, "Still alive at 40 HP")
	assert_eq(killers.size(), 0, "died must not emit above 0 HP")

	hc.apply_damage(75.0, 42, 1)
	assert_almost_eq(hc.current, 0.0, 0.001, "Health must clamp at 0.0 on overkill")
	assert_true(hc.is_dead, "is_dead must be true at 0 HP")
	assert_eq(killers.size(), 1, "died must emit exactly once")
	assert_eq(killers[0], 42, "died must pass killer source_id")
	assert_eq(damaged_amounts.size(), 2, "Two fatal/pre-fatal hits recorded")

	hc.apply_damage(25.0, 99, 0)
	hc.apply_damage(100.0, 99, 1)
	assert_almost_eq(hc.current, 0.0, 0.001, "Dead health must stay 0.0")
	assert_eq(killers.size(), 1, "died must not emit again when already dead")
	assert_eq(damaged_amounts.size(), 2, "Damage to dead entity must be ignored")


func test_heal_clamps_to_max_and_ignores_dead_entity() -> void:
	var hc: HealthComponent = HealthComponent.new()
	add_child_autofree(hc)
	var changed_log: Array[Vector2] = []
	hc.health_changed.connect(func(cur: float, max_val: float) -> void:
		changed_log.append(Vector2(cur, max_val))
	)

	hc.apply_damage(50.0, 1, 0)
	assert_almost_eq(hc.current, 50.0, 0.001)
	assert_eq(changed_log.size(), 1)

	hc.heal(0.0)
	hc.heal(-10.0)
	assert_almost_eq(hc.current, 50.0, 0.001, "Zero/negative heal must be ignored")
	assert_eq(changed_log.size(), 1)

	hc.heal(30.0)
	assert_almost_eq(hc.current, 80.0, 0.001, "Heal by 30 must reach 80 HP")
	assert_eq(changed_log.size(), 2)

	hc.heal(50.0)
	assert_almost_eq(hc.current, 100.0, 0.001, "Heal must not exceed max_health")
	assert_eq(changed_log.size(), 3)

	hc.apply_damage(120.0, 5, 0)
	assert_true(hc.is_dead, "Must be dead after 120 damage")
	hc.heal(50.0)
	assert_almost_eq(hc.current, 0.0, 0.001, "Cannot heal a dead entity without reset()")
	assert_true(hc.is_dead, "Dead entity remains dead on heal()")


func test_reset_restores_full_health_and_clears_dead_flag() -> void:
	var hc: HealthComponent = HealthComponent.new()
	add_child_autofree(hc)
	var died_killers: Array[int] = []
	hc.died.connect(func(killer_id: int) -> void:
		died_killers.append(killer_id)
	)

	hc.apply_damage(100.0, 10, 0)
	assert_true(hc.is_dead, "Entity must be dead")
	assert_almost_eq(hc.current, 0.0, 0.001)
	assert_eq(died_killers.size(), 1)

	hc.reset()
	assert_false(hc.is_dead, "reset() must clear is_dead")
	assert_almost_eq(hc.current, hc.max_health, 0.001, "reset() must restore current to max_health")

	hc.apply_damage(100.0, 11, 0)
	assert_true(hc.is_dead, "Entity can die again after reset()")
	assert_eq(died_killers.size(), 2, "died signal must emit again after respawn reset()")


func test_optional_regeneration_disabled_by_default_and_works_when_configured() -> void:
	var hc: HealthComponent = HealthComponent.new()
	add_child_autofree(hc)
	assert_false(hc.regen_enabled, "Regeneration must be disabled by default")
	assert_almost_eq(hc.regen_rate, 0.0, 0.001, "Default regen_rate must be 0.0")

	hc.apply_damage(40.0, 1, 0)
	hc.step_regen(10.0)
	assert_almost_eq(hc.current, 60.0, 0.001, "Health must not regenerate when disabled")

	hc.regen_delay = 2.0
	hc.regen_rate = 15.0
	assert_true(hc.regen_enabled, "Setting positive regen_rate enables regeneration")

	hc.step_regen(1.5)
	assert_almost_eq(hc.current, 60.0, 0.001, "Must not regenerate before regen_delay (2.0 s)")

	hc.apply_damage(10.0, 1, 0)
	assert_almost_eq(hc.current, 50.0, 0.001, "Damage resets regen delay timer")
	hc.step_regen(1.5)
	assert_almost_eq(hc.current, 50.0, 0.001, "Still waiting for 2.0 s after new damage")

	hc.step_regen(1.0)
	assert_almost_eq(hc.current, 65.0, 0.001, "At 2.5 s total (>= 2.0 s delay), 1.0 s step heals 15 HP")

	hc.step_regen(5.0)
	assert_almost_eq(hc.current, 100.0, 0.001, "Regeneration must cap at max_health")


func test_player_scene_contains_health_component() -> void:
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	var player: Player = packed.instantiate() as Player
	add_child_autofree(player)
	var hc: HealthComponent = player.get_node_or_null("HealthComponent") as HealthComponent
	assert_not_null(hc, "Player scene must have a HealthComponent child node")
	assert_almost_eq(hc.current, 100.0, 0.001, "Player HealthComponent must start at 100 HP")
	player.apply_fall_damage(25.0)
	assert_almost_eq(hc.current, 75.0, 0.001, "Player.apply_fall_damage must reduce HealthComponent current")
