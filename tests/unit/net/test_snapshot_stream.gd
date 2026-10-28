extends GutTest

var _loader: MapLoader
var _stream: SnapshotStream


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	_loader = MapLoader.new()
	add_child(_loader)
	assert_eq(_loader.load_map("testbed"), OK)
	_stream = _loader.players.snapshots


func after_each() -> void:
	_loader.unload_map()
	_loader.free()
	await get_tree().process_frame


func test_atomic_validation_and_monotonic_packets() -> void:
	var packet: PackedByteArray = _packet(2, 2)
	packet[SnapshotCodec.HEADER_BYTES + SnapshotCodec.PLAYER_BYTES + 20] = 3
	assert_false(_stream.accept_packet(packet))
	assert_eq(_stream.last_received_tick, 0)
	assert_eq(_stream.received_packets, 0)
	packet = _packet(2, 2)
	packet.encode_u32(SnapshotCodec.HEADER_BYTES + SnapshotCodec.PLAYER_BYTES, 42)
	assert_false(_stream.accept_packet(packet), "Duplicate peer id rejects the entire packet")
	packet = _packet(2, 2)
	assert_true(_stream.accept_packet(packet))
	assert_false(_stream.accept_packet(packet), "Duplicate server tick")
	assert_false(_stream.accept_packet(_packet(1, 2)), "Out of order server tick")
	assert_eq(_stream.received_packets, 1)
	assert_eq(_stream.last_received_tick, 2)
	assert_eq(_stream.last_processed_input_tick, 123)
	assert_eq(_stream.received_bytes, packet.size())


func test_owner_state_is_acknowledged_without_local_simulation_or_mutations() -> void:
	var actor: Player = preload("res://src/player/player.tscn").instantiate() as Player
	actor.network_owner_id = 1
	_loader.add_child(actor)
	_loader.players.actors[1] = actor
	_stream.track(actor)
	var packet: PackedByteArray = _packet(2, 1)
	packet.encode_u32(SnapshotCodec.HEADER_BYTES, 1)
	var before: Transform3D = actor.transform
	var ammo: int = actor.weapon.ammo_in_mag
	assert_true(_stream.accept_packet(packet))
	assert_eq(actor.transform, before)
	assert_eq(actor.weapon.ammo_in_mag, ammo)
	assert_eq(actor.remote_view.interpolator.count, 0)
	assert_eq(actor.server_sim.simulated_ticks, 0)
	assert_eq(_stream.last_processed_input_tick, 123)
	_stream.untrack(actor)
	_loader.players.actors.clear()
	actor.free()


func test_remote_view_samples_world_pose_stance_angles_and_weapon_only() -> void:
	var actor: Player = preload("res://src/player/player.tscn").instantiate() as Player
	actor.network_owner_id = 42
	_loader.add_child(actor)
	_loader.players.actors[42] = actor
	_stream.track(actor)
	var before: Transform3D = actor.transform
	assert_true(_stream.accept_packet(_packet(100, 1)))
	assert_true(actor.remote_view.present_at(106.0))
	assert_almost_eq(actor.remote_view.global_position.x, 5.0, 0.004)
	assert_almost_eq(actor.remote_view.global_rotation.y, 1.0, 0.0001)
	assert_eq(actor.remote_view.flags & PlayerSnapshot.STANCE_MASK, PlayerStance.CROUCH)
	assert_eq(actor.remote_view.weapon_id, 456)
	assert_almost_eq(actor.remote_view.capsule.position.y, 0.6, 0.0001)
	assert_eq(actor.transform, before, "Presentation cannot move the simulation body")
	assert_eq(actor.server_sim.simulated_ticks, 0)
	var nodes: int = get_tree().get_node_count()
	for frame: int in range(120):
		actor.remote_view.present_at(106.0 + float(frame) / 120.0)
	assert_eq(get_tree().get_node_count(), nodes)
	_stream.untrack(actor)
	_loader.players.actors.clear()
	actor.free()


func test_reset_unloads_transport_and_rpc_without_sender_is_ignored() -> void:
	_stream.receive_snapshot(_packet(2, 1))
	assert_eq(_stream.received_packets, 0)
	assert_true(_stream.accept_packet(_packet(2, 1)))
	var stale: PackedByteArray = _packet(4, 1)
	_loader.unload_map()
	assert_eq(_stream.last_received_tick, 0)
	assert_eq(_stream.last_processed_input_tick, 0)
	assert_eq(_stream.received_bytes, 0)
	assert_false(_stream.accept_packet(stale))


func _packet(tick: int, count: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(SnapshotCodec.packet_size(count))
	bytes.encode_u32(0, tick)
	bytes.encode_u16(4, count)
	bytes.encode_u32(6, 123)
	var state: PlayerSnapshot = PlayerSnapshot.new()
	state.position.x = 5.0
	state.yaw = 1.0
	state.flags = PlayerStance.CROUCH
	state.weapon_id = 456
	for index: int in range(count):
		state.peer_id = 42 + index
		SnapshotCodec.encode_into(state, _loader.current_data.snapshot_config, bytes,
			SnapshotCodec.HEADER_BYTES + index * SnapshotCodec.PLAYER_BYTES)
	return bytes
