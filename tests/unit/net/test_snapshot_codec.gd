extends GutTest

var _config: SnapshotConfig = preload("res://src/net/default_snapshot.tres")


func test_roundtrip_quantization_bounds_and_all_fields() -> void:
	var source: PlayerSnapshot = PlayerSnapshot.new()
	source.peer_id = 0x7fffffff
	source.position = Vector3(-128.321, 9.876, 144.556)
	source.velocity = Vector3(-6.5, 15.0, 0.25)
	source.yaw = -3.1
	source.pitch = 1.2
	source.flags = PlayerStance.CROUCH | PlayerSnapshot.SPRINTING | PlayerSnapshot.AIMING
	source.weapon_id = 0xf1234567
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(SnapshotCodec.PLAYER_BYTES)
	assert_true(SnapshotCodec.encode_into(source, _config, bytes))
	var decoded: PlayerSnapshot = PlayerSnapshot.new()
	assert_true(SnapshotCodec.decode_into(bytes, 0, _config, decoded))
	assert_eq(decoded.peer_id, source.peer_id)
	assert_eq(decoded.flags, source.flags)
	assert_eq(decoded.weapon_id, source.weapon_id)
	for axis: int in range(3):
		var position_error: float = (_config.position_max[axis] - _config.position_min[axis]) / 131070.0
		assert_almost_eq(decoded.position[axis], source.position[axis], position_error + 0.00002)
		assert_almost_eq(decoded.velocity[axis], source.velocity[axis], _config.velocity_limit / 65535.0 + 0.00001)
	assert_almost_eq(decoded.yaw, source.yaw, PI / 65535.0)
	assert_almost_eq(decoded.pitch, source.pitch, PI / 131070.0)


func test_extremes_saturation_and_little_endian_offsets() -> void:
	var source: PlayerSnapshot = PlayerSnapshot.new()
	source.peer_id = 0x12345678
	source.position = _config.position_max + Vector3.ONE
	source.velocity = -Vector3.ONE * _config.velocity_limit * 2.0
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(SnapshotCodec.PLAYER_BYTES)
	assert_true(SnapshotCodec.encode_into(source, _config, bytes))
	assert_eq(bytes.slice(0, 4), PackedByteArray([0x78, 0x56, 0x34, 0x12]))
	var decoded: PlayerSnapshot = PlayerSnapshot.new()
	assert_true(SnapshotCodec.decode_into(bytes, 0, _config, decoded))
	assert_eq(decoded.position, _config.position_max)
	assert_eq(decoded.velocity, -Vector3.ONE * _config.velocity_limit)


func test_reject_invalid_state_offsets_and_malformed_headers() -> void:
	var source: PlayerSnapshot = PlayerSnapshot.new()
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(SnapshotCodec.packet_size(1))
	assert_false(SnapshotCodec.encode_into(source, _config, bytes, 10))
	source.peer_id = 1
	source.position.x = NAN
	assert_false(SnapshotCodec.encode_into(source, _config, bytes, 10))
	source.position = Vector3.ZERO
	source.flags = 3
	assert_false(SnapshotCodec.encode_into(source, _config, bytes, 10))
	source.flags = 0
	assert_false(SnapshotCodec.encode_into(source, _config, bytes, 11))
	assert_false(SnapshotCodec.decode_into(bytes, -1, _config, source))
	assert_false(SnapshotCodec.valid_packet(bytes, 32))
	bytes.encode_u32(0, 2)
	bytes.encode_u16(4, 1)
	assert_true(SnapshotCodec.valid_packet(bytes, 32))
	assert_false(SnapshotCodec.valid_packet(bytes, 0))
	assert_false(SnapshotCodec.valid_packet(bytes.slice(0, bytes.size() - 1), 32))
	bytes.encode_u16(4, 2)
	assert_false(SnapshotCodec.valid_packet(bytes, 32))


func test_configuration_and_weapon_ids_have_no_collisions() -> void:
	assert_true(_config.is_valid())
	var invalid: SnapshotConfig = _config.duplicate() as SnapshotConfig
	invalid.position_max = invalid.position_min
	assert_false(invalid.is_valid())
	invalid = _config.duplicate() as SnapshotConfig
	invalid.extrapolation_seconds = 0.2
	assert_false(invalid.is_valid())
	var ids: Dictionary[int, StringName] = {}
	_check_weapons("res://src/weapons/data", ids)
	assert_gt(ids.size(), 17)


func _check_weapons(path: String, ids: Dictionary[int, StringName]) -> void:
	var directory: DirAccess = DirAccess.open(path)
	for folder: String in directory.get_directories():
		_check_weapons(path.path_join(folder), ids)
	for file: String in directory.get_files():
		if not file.ends_with(".tres"):
			continue
		var weapon: WeaponData = load(path.path_join(file)) as WeaponData
		if weapon == null:
			continue
		var wire_id: int = weapon.id.hash() & SnapshotCodec.UINT_MAX
		assert_ne(wire_id, 0)
		assert_false(ids.has(wire_id) and ids[wire_id] != weapon.id, "Wire id collision")
		ids[wire_id] = weapon.id
