extends GutTest

var _patient: Player
var _attacker: Player


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
	_patient = _player(Vector3(4200, 10, 4200))
	_attacker = _player(_patient.position + Vector3(0, 0, 1))
	_patient.health_component.apply_damage(100.0)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _aim() -> Transform3D:
	var origin: Vector3 = _patient.head.global_position + Vector3(0, 0, 1)
	return Transform3D(Basis.IDENTITY, origin)


func test_real_hitscan_finishes_downed_patient() -> void:
	await _setup()
	var data: WeaponData = _attacker.weapon.data.duplicate() as WeaponData
	data.spread_hip_deg = 0.0
	data.spread_ads_deg = 0.0
	_attacker.weapon.setup(data)
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.buttons = PlayerInput.BTN_FIRE
	_attacker.weapon_hitscan.simulate(inp, _aim())
	assert_eq(_patient.life.state, PlayerLife.State.SPAWN_SELECT)
	assert_eq(_attacker.weapon.ammo_in_mag, data.mag_size - 1)


func test_real_knife_contact_finishes_downed_patient() -> void:
	await _setup()
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.melee = true
	var knife: MeleeAttack = _attacker.equipment.melee
	knife.simulate(inp, _aim(), _attacker.position)
	inp.tick = 1 + ceili(knife.data.hit_delay * Engine.physics_ticks_per_second)
	inp.melee = false
	knife.simulate(inp, _aim(), _attacker.position)
	assert_eq(_patient.life.state, PlayerLife.State.SPAWN_SELECT)


func test_real_explosion_finishes_downed_patient() -> void:
	await _setup()
	var explosion: Explosion = Explosion.new()
	add_child_autofree(explosion)
	var profile: ProjectileData = load("res://src/weapons/projectiles/frag.tres") as ProjectileData
	explosion.apply(profile, _patient.position + Vector3.UP * 0.6, 7)
	assert_eq(_patient.life.state, PlayerLife.State.SPAWN_SELECT)


func test_client_medic_cannot_advance_hold_or_revive() -> void:
	await _setup()
	_attacker.class_data = load("res://src/classes/data/medic.tres") as ClassData
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 9), OK)
	api.multiplayer_peer = peer
	var path: NodePath = _attacker.get_path()
	get_tree().set_multiplayer(api, path)
	var inp: PlayerInput = PlayerInput.new()
	inp.buttons = PlayerInput.BTN_INTERACT
	for tick: int in range(181):
		inp.tick = tick
		_attacker.life.interaction.simulate(inp, 1.0 / 60.0)
	assert_null(_attacker.life.interaction.target)
	assert_eq(_attacker.life.interaction.progress, 0.0)
	assert_eq(_patient.life.state, PlayerLife.State.DOWNED)
	get_tree().set_multiplayer(null, path)
	peer.close()


func test_revive_under_low_ceiling_preserves_valid_capsule() -> void:
	await _setup()
	var ceiling: StaticBody3D = StaticBody3D.new()
	ceiling.position = _patient.position + Vector3.UP
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(3, 0.1, 3)
	col.shape = shape
	ceiling.add_child(col)
	add_child_autofree(ceiling)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(_patient.life.revive())
	assert_eq(_patient.stance, PlayerStance.PRONE)
	assert_eq(_patient.life.state, PlayerLife.State.ALIVE)
	assert_eq(_patient.health_component.current, 30.0)
