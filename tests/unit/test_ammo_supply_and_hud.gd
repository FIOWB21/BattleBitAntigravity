extends GutTest

var _world: Node3D
var _actor: CharacterBody3D
var _weapon: Weapon
var _receiver: AmmoReceiver
var _box: AmmoBox
var _hud: HUD


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_world = Node3D.new()
	_actor = CharacterBody3D.new()
	_actor.name = "Player"
	_actor.collision_layer = 2
	_actor.position = Vector3(5.0, 0.0, 0.0)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.position.y = 0.5
	_actor.add_child(shape)
	_weapon = Weapon.new()
	_weapon.name = "Weapon"
	_weapon.data = WeaponData.new()
	_weapon.data.reload_time = 0.2
	_weapon.ticks_per_second = 60
	_actor.add_child(_weapon)
	_receiver = AmmoReceiver.new()
	_receiver.name = "AmmoReceiver"
	_receiver.weapon = _weapon
	_actor.add_child(_receiver)
	_world.add_child(_actor)
	_box = (load("res://src/maps/testbed/ammo_box.tscn") as PackedScene).instantiate() as AmmoBox
	_world.add_child(_box)
	_hud = (load("res://src/ui/hud/hud.tscn") as PackedScene).instantiate() as HUD
	_world.add_child(_hud)
	add_child_autofree(_world)
	_weapon.set_physics_process(false)


func _step(tick: int, buttons: int = 0) -> void:
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = tick
	inp.buttons = buttons
	_weapon.simulate(inp)


func test_receiver_uses_fraction_of_capacity_caps_reserve_and_never_loads_magazine() -> void:
	_weapon.reserve_ammo = 0
	assert_eq(_receiver.add_ammo(0.25), 37)
	assert_eq(_weapon.reserve_ammo, 37)
	assert_eq(_receiver.add_ammo(1.0), 113)
	assert_eq(_weapon.reserve_ammo, 150)
	assert_eq(_receiver.add_ammo(1.0), 0)
	assert_eq(_weapon.ammo_in_mag, 30)
	_weapon.reserve_ammo = 0
	assert_eq(_receiver.add_ammo(100.0), 150)


func test_invalid_and_sub_round_fractions_do_not_grant_ammo_or_emit_events() -> void:
	_weapon.reserve_ammo = 0
	var events: Array[int] = []
	_weapon.ammo_changed.connect(func(_mag: int, reserve: int) -> void: events.append(reserve))
	for fraction: float in [-1.0, 0.0, NAN, INF, -INF, 0.001]:
		assert_eq(_receiver.add_ammo(fraction), 0)
	assert_eq(_weapon.add_reserve_ammo(-1), 0)
	assert_eq(_weapon.add_reserve_ammo(0), 0)
	assert_eq(_weapon.reserve_ammo, 0)
	assert_eq(events.size(), 0)
	_receiver.weapon = null
	assert_eq(_receiver.add_ammo(1.0), 0)


func test_supply_during_reload_is_transferred_only_at_completion() -> void:
	_weapon.ammo_in_mag = 1
	_weapon.reserve_ammo = 3
	_step(0, PlayerInput.BTN_RELOAD)
	assert_eq(_box.supply(_actor), 147)
	assert_eq(_weapon.ammo_in_mag, 1)
	_step(12)
	assert_eq(_weapon.ammo_in_mag, 31)
	assert_eq(_weapon.reserve_ammo, 120)
	assert_eq(_hud.ammo_label.text, "31 / 120")


func test_box_only_reports_actual_supplies_and_rejects_objects_without_receiver() -> void:
	var supplied: Array[int] = []
	_box.supplied.connect(func(_body: Node3D, amount: int) -> void: supplied.append(amount))
	assert_eq(_box.supply(_actor), 0)
	_weapon.reserve_ammo = 149
	assert_eq(_box.supply(_actor), 1)
	assert_eq(_box.supply(_actor), 0)
	assert_eq(_box.supply(_world), 0)
	assert_eq(_box.supply(null), 0)
	assert_eq(supplied, [1])


func test_real_body_entry_into_box_replenishes_reserve_and_updates_hud() -> void:
	_weapon.reserve_ammo = 10
	for frame: int in range(3):
		await get_tree().physics_frame
	_actor.position = Vector3.ZERO
	for frame: int in range(3):
		await get_tree().physics_frame
	assert_eq(_weapon.reserve_ammo, 150)
	assert_eq(_hud.ammo_label.text, "30 / 150")
	print("ACCEPT 2.5: physical ammo-box entry replenishes reserve; HUD shows 30 / 150")


func test_hud_tracks_shots_tactical_reload_and_supply_via_signals() -> void:
	assert_eq(_hud.ammo_label.text, "30 / 150")
	_step(0, PlayerInput.BTN_FIRE)
	assert_eq(_hud.ammo_label.text, "29 / 150")
	_step(1, PlayerInput.BTN_RELOAD)
	_step(13)
	assert_eq(_hud.ammo_label.text, "31 / 148")
	assert_eq(_receiver.add_ammo(1.0), 2)
	assert_eq(_hud.ammo_label.text, "31 / 150")
	_hud.unbind_all()
	_step(14, PlayerInput.BTN_FIRE)
	assert_eq(_hud.ammo_label.text, "31 / 150")


func test_hud_rebind_disconnects_previous_weapon_and_null_binding_clears_display() -> void:
	var other: Weapon = Weapon.new()
	other.data = WeaponData.new()
	_world.add_child(other)
	_hud.bind_weapon(other)
	_step(0, PlayerInput.BTN_FIRE)
	assert_eq(_hud.ammo_label.text, "30 / 150")
	other.ammo_changed.emit(3, 9)
	assert_eq(_hud.ammo_label.text, "3 / 9")
	_hud.bind_weapon(other)
	assert_eq(_hud.ammo_label.text, "30 / 150")
	_hud.bind_weapon(null)
	assert_eq(_hud.ammo_label.text, "0 / 0")
	other.ammo_changed.emit(1, 2)
	assert_eq(_hud.ammo_label.text, "0 / 0")


func test_network_client_cannot_supply_shoot_or_emit_empty_click() -> void:
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 9), OK)
	api.multiplayer_peer = peer
	var path: NodePath = _world.get_path()
	get_tree().set_multiplayer(api, path)
	_weapon.ammo_in_mag = 0
	_weapon.reserve_ammo = 10
	var clicks: Array[int] = []
	_weapon.dry_fired.connect(func(tick: int) -> void: clicks.append(tick))
	assert_eq(_receiver.add_ammo(1.0), 0)
	assert_eq(_box.supply(_actor), 0)
	assert_eq(_weapon.add_reserve_ammo(1), 0)
	_step(0, PlayerInput.BTN_FIRE)
	_step(1, PlayerInput.BTN_RELOAD)
	assert_eq(_weapon.ammo_in_mag, 0)
	assert_eq(_weapon.reserve_ammo, 10)
	assert_eq(_weapon.state, Weapon.State.IDLE)
	assert_eq(clicks.size(), 0)
	get_tree().set_multiplayer(null, path)
	peer.close()


func test_player_scene_wires_receiver_audio_hud_and_actual_sprint_cancellation() -> void:
	var bed: Node3D = (load("res://src/maps/testbed/testbed.tscn") as PackedScene).instantiate() as Node3D
	var player: Player = bed.get_node("Player") as Player
	player.is_local_player = false
	add_child_autofree(bed)
	var receiver: AmmoReceiver = player.get_node("AmmoReceiver") as AmmoReceiver
	assert_eq(receiver.weapon, player.weapon)
	var click: WeaponDryFire = player.weapon.get_node("DryFire") as WeaponDryFire
	assert_not_null(click.stream as AudioStreamWAV)
	assert_true(player.weapon.dry_fired.is_connected(click._on_dry_fired))
	assert_not_null(bed.get_node("AmmoBox") as AmmoBox)
	var inp: PlayerInput = PlayerInput.new()
	for tick: int in range(15):
		await get_tree().physics_frame
		inp.tick = tick
		player.step_simulation(inp, 1.0 / 60.0)
	assert_true(player.is_on_floor())
	player.weapon.ammo_in_mag = 7
	inp.tick = 15
	inp.buttons = PlayerInput.BTN_RELOAD
	player.step_simulation(inp, 1.0 / 60.0)
	assert_eq(player.weapon.state, Weapon.State.RELOADING)
	inp.tick = 16
	inp.buttons = PlayerInput.BTN_SPRINT
	inp.move = Vector2(0.0, 1.0)
	player.step_simulation(inp, 1.0 / 60.0)
	assert_true(player.motor.is_sprinting)
	assert_eq(player.weapon.state, Weapon.State.BLOCKED)
	assert_eq(player.weapon.reload_end_tick, -1)
	assert_eq(player.weapon.ammo_in_mag, 7)
