extends GutTest

var _loader: MapLoader
var _actor: Player
var _events: WeaponPresentation
var _state: PlayerSnapshot


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_loader = MapLoader.new()
	add_child(_loader)
	assert_eq(_loader.load_map("testbed"), OK)
	var players: NetworkPlayers = _loader.players
	players._slots[42] = 0
	_actor = players._spawn_player({"peer_id": 42, "pose": _loader.spawn_pose}) as Player
	players._container.add_child(_actor)
	_events = players.weapon_presentation
	_state = PlayerSnapshot.new()
	_state.tick = 100
	_state.peer_id = 42
	_state.weapon_id = _actor.weapon.data.id.hash() & SnapshotCodec.UINT_MAX
	_state.position = Vector3(5.0, 0.0, 7.0)
	_freeze(_loader)


func after_each() -> void:
	_loader.free()
	Game.set_state(Game.State.MENU)


func test_reload_bit_roundtrips_without_increasing_public_packet_size() -> void:
	_state.flags = PlayerSnapshot.RELOADING | PlayerSnapshot.AIMING | PlayerStance.CROUCH
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(SnapshotCodec.PLAYER_BYTES)
	assert_true(SnapshotCodec.encode_into(_state, _loader.current_data.snapshot_config, bytes))
	var out: PlayerSnapshot = PlayerSnapshot.new()
	assert_true(SnapshotCodec.decode_into(bytes, 0, _loader.current_data.snapshot_config, out))
	assert_eq(out.flags, _state.flags)
	assert_eq(out.weapon_id, _state.weapon_id)
	assert_eq(bytes.size(), 25)
	assert_eq(SnapshotCodec.packet_size(3), 85)


func test_server_captures_only_active_public_weapon_and_reload_aim_stance() -> void:
	_actor.stance = PlayerStance.CROUCH
	_actor.ads.target = 1.0
	_actor.weapon.state = Weapon.State.RELOADING
	var stream: SnapshotStream = _loader.players.snapshots
	stream._capture(_actor)
	assert_eq(stream._state.weapon_id, _state.weapon_id)
	assert_true((stream._state.flags & PlayerSnapshot.RELOADING) != 0)
	assert_true((stream._state.flags & PlayerSnapshot.AIMING) != 0)
	assert_eq(stream._state.flags & PlayerSnapshot.STANCE_MASK, PlayerStance.CROUCH)
	_actor.weapon.state = Weapon.State.IDLE
	_actor.ads.target = 0.0
	stream._capture(_actor)
	assert_eq(stream._state.flags & (PlayerSnapshot.RELOADING | PlayerSnapshot.AIMING), 0)


func test_public_pose_updates_world_model_without_mutating_remote_gameplay() -> void:
	var before: Transform3D = _actor.global_transform
	var magazine: int = _actor.weapon.ammo_in_mag
	var reserve: int = _actor.weapon.reserve_ammo
	_state.flags = PlayerStance.CROUCH | PlayerSnapshot.AIMING | PlayerSnapshot.RELOADING
	_state.pitch = 0.4
	_present()
	var view: WorldWeaponView = _actor.remote_view.weapon_view
	assert_true(view.visible)
	assert_true(view.model.visible)
	assert_true(view.is_reloading)
	assert_true(view.is_aiming)
	assert_eq(view.model.position, view.config.aimed_offset)
	assert_almost_eq(view.position.y, _actor.movement_config.crouch_head_height, 0.00001)
	assert_almost_eq(view.rotation.x, _state.pitch, 0.00001)
	assert_eq(_actor.global_transform, before)
	assert_eq(_actor.weapon.ammo_in_mag, magazine)
	assert_eq(_actor.weapon.reserve_ammo, reserve)
	assert_eq(_actor.weapon.state, Weapon.State.IDLE)
	assert_eq(_actor.server_sim.simulated_ticks, 0)


func test_weapon_changes_reuse_models_unknown_and_empty_ids_hide_them() -> void:
	_present()
	var view: WorldWeaponView = _actor.remote_view.weapon_view
	var rifle: Node3D = view.model
	_state.weapon_id = _actor.inventory.weapon_at(Loadout.Slot.SECONDARY).data.id.hash() & SnapshotCodec.UINT_MAX
	_state.tick += 2
	_present()
	assert_ne(view.model, rifle)
	assert_false(rifle.visible)
	assert_eq(view.model.scale, view.config.pistol_scale)
	var nodes: int = get_tree().get_node_count()
	for id: int in [0, 123, _actor.weapon.data.id.hash() & SnapshotCodec.UINT_MAX]:
		_state.weapon_id = id
		_state.tick += 2
		_present()
		assert_eq(view.visible, id == _actor.weapon.data.id.hash() & SnapshotCodec.UINT_MAX)
	assert_eq(view.model, rifle)
	assert_eq(get_tree().get_node_count(), nodes)


func test_reload_animation_advances_and_clears_on_cancel_death_and_spawn() -> void:
	_state.flags = PlayerSnapshot.RELOADING
	_present()
	var view: WorldWeaponView = _actor.remote_view.weapon_view
	view.advance(view.config.reload_cycle_seconds * 0.5)
	assert_ne(view.model.rotation, Vector3.ZERO)
	assert_ne(view.model.position, view.config.held_offset)
	_state.flags = 0
	_state.tick += 2
	_present()
	assert_false(view.is_reloading)
	assert_eq(view.model.rotation, Vector3.ZERO)
	_state.flags = PlayerSnapshot.RELOADING | PlayerSnapshot.DEAD
	_state.tick += 2
	_present()
	assert_false(view.visible)
	assert_false(view.is_reloading)
	_actor.remote_view.reset_for_spawn(Transform3D.IDENTITY, 200)
	assert_eq(view.weapon_id, 0)
	assert_null(view.model)


func test_remote_event_pulses_flash_and_spatial_audio_once_without_gameplay() -> void:
	_present()
	var health: float = _actor.health_component.current
	var ammo: int = _actor.weapon.ammo_in_mag
	var pose: Transform3D = _actor.remote_view.weapon_view.muzzle_pose()
	assert_true(_events.present_shot(42, 100, _state.weapon_id))
	assert_eq(_events.presented_shots, 1)
	assert_true((_events.flashes.items[0] as MuzzleFlash).visible)
	assert_eq((_events.flashes.items[0] as MuzzleFlash).global_transform, pose)
	var voice: AudioStreamPlayer3D = _events.audio.pool.items[0] as AudioStreamPlayer3D
	assert_eq(voice.global_position, pose.origin)
	assert_eq(voice.max_distance, _events.config.audio_distance)
	assert_gt(voice.max_distance, 100.0)
	assert_not_null(voice.stream)
	assert_true(_actor.remote_view.weapon_view.is_firing)
	assert_false(_events.present_shot(42, 100, _state.weapon_id))
	assert_false(_events.present_shot(42, 99, _state.weapon_id))
	assert_eq(_actor.health_component.current, health)
	assert_eq(_actor.weapon.ammo_in_mag, ammo)
	for projectile: Projectile in _actor.equipment.projectiles.system.projectiles:
		assert_false(projectile.active)


func test_invalid_events_and_direct_rpc_without_sender_are_ignored() -> void:
	_present()
	assert_false(_events.present_shot(999, 100, _state.weapon_id))
	assert_false(_events.present_shot(42, 100, 123))
	_events.remote_shot(42, 100, _state.weapon_id)
	assert_eq(_events.presented_shots, 0)
	_actor.remote_view.reset_for_spawn(Transform3D.IDENTITY, 200)
	assert_false(_events.present_shot(42, 199, _state.weapon_id))
	assert_false(_events.present_shot(42, 200, _state.weapon_id))
	assert_true(_events.present_shot(42, 201, _state.weapon_id))


func test_effect_pools_and_model_nodes_remain_bounded_during_sustained_fire() -> void:
	_present()
	var view: WorldWeaponView = _actor.remote_view.weapon_view
	var nodes: int = get_tree().get_node_count()
	for tick: int in range(100, 400):
		assert_true(_events.present_shot(42, tick, _state.weapon_id))
		view.advance(1.0 / 60.0)
	assert_eq(_events.flashes.items.size(), _events.config.flash_capacity)
	assert_eq(_events.audio.pool.items.size(), ShotAudio.CAPACITY)
	assert_eq(get_tree().get_node_count(), nodes)
	view.advance(view.config.firing_seconds)
	assert_false(view.is_firing)
	_events.reset()
	for flash: MuzzleFlash in _events.flashes.items:
		assert_false(flash.visible)
	assert_null(_actor.equipment.effects, "World events replace remote local traces")


func test_untracking_disconnects_server_source_and_clears_deduplication() -> void:
	_events.untrack(_actor)
	assert_false(_events._last_shots.has(42))
	assert_false(_events._bindings.has(_actor.weapon))
	_events.track(_actor)
	assert_true(_events._bindings.has(_actor.weapon))


func test_only_accepted_server_discharge_publishes_remote_cosmetics() -> void:
	_present()
	var connected: bool = Net.is_connected
	Net.is_connected = true
	var input: PlayerInput = PlayerInput.new()
	input.tick = Net.tick
	_actor.weapon.simulate(input)
	_actor.weapon.ammo_in_mag = 0
	assert_false(_actor.weapon.fire_requested(Net.tick))
	assert_eq(_events.presented_shots, 0)
	_actor.weapon.ammo_in_mag = 1
	assert_true(_actor.weapon.fire_requested(Net.tick))
	assert_eq(_events.presented_shots, 1)
	assert_eq(_actor.weapon.ammo_in_mag, 0)
	Net.is_connected = connected


func test_local_owner_and_dedicated_server_have_no_remote_weapon_effects() -> void:
	var players: NetworkPlayers = _loader.players
	players._slots[1] = 1
	var owner: Player = players._spawn_player({"peer_id": 1, "pose": _loader.spawn_pose}) as Player
	players._container.add_child(owner)
	_freeze(owner)
	assert_null(owner.remote_view.weapon_view)
	assert_false(_events.present_shot(1, 100, _state.weapon_id))
	var dedicated: bool = Game.is_dedicated
	Game.is_dedicated = true
	var server_events: WeaponPresentation = WeaponPresentation.new()
	add_child(server_events)
	assert_null(server_events.flashes)
	assert_null(server_events.audio)
	assert_false(server_events.is_processing())
	server_events.free()
	Game.is_dedicated = dedicated


func test_event_before_first_snapshot_has_a_world_muzzle_at_head_height() -> void:
	var view: WorldWeaponView = _actor.remote_view.weapon_view
	assert_null(view.model)
	assert_false(view.visible)
	var pose: Transform3D = view.muzzle_pose(_state.weapon_id)
	assert_gt(pose.origin.y, _actor.global_position.y + 1.0)
	assert_true(_events.present_shot(42, 100, _state.weapon_id))
	assert_eq((_events.flashes.items[0] as MuzzleFlash).global_transform, pose)


func _present() -> void:
	_actor.remote_view.push_snapshot(_state)
	assert_true(_actor.remote_view.present_at(float(_state.tick + 6)))


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_freeze(child)
