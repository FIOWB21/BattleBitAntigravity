extends GutTest

var _player: Player
var _console: DebugConsole


func before_each() -> void:
	_player = (load("res://src/player/player.tscn") as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	_player.release_mouse()
	_console = DebugConsole.new()


func _command(text: String) -> String:
	return _console.execute_command("attachment " + text)


func test_console_equips_and_removes_and_updates_real_simulation_spread() -> void:
	var before: float = _player.weapon_hitscan.handling.spread_degrees(false, PlayerStance.STAND, 0.0)
	assert_has(_command("equip grip"), "test_grip")
	var after: float = _player.weapon_hitscan.handling.spread_degrees(false, PlayerStance.STAND, 0.0)
	assert_almost_eq(after, before * 0.8, 0.000001)
	assert_has(_command("list"), "hip=")
	assert_has(_command("remove grip"), "attachments=[]")
	assert_eq(_player.weapon_hitscan.handling.spread_degrees(false, PlayerStance.STAND, 0.0), before)


func test_real_fired_ray_changes_cone_with_same_input_seed_and_consumes_one_round() -> void:
	var base: WeaponData = _player.weapon.data
	var directions: Array[Vector3] = []
	_player.weapon_hitscan.shot_traced.connect(
		func(_tick: int, _pellet: int, direction: Vector3, _hit: HitResult) -> void:
			directions.append(direction))
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 1
	inp.buttons = PlayerInput.BTN_FIRE
	var aim: Transform3D = Transform3D(Basis.IDENTITY, Vector3(40.0, 10.0, 40.0))
	_player.weapon_hitscan.simulate(inp, aim)
	assert_eq(directions.size(), 1)
	_player.weapon.setup(base)
	assert_false(_command("equip grip").begins_with("Error"))
	_player.weapon_hitscan.simulate(inp, aim)
	assert_eq(directions.size(), 2)
	assert_lt(Vector3.FORWARD.angle_to(directions[1]), Vector3.FORWARD.angle_to(directions[0]))
	var expected: Vector3 = _player.weapon_hitscan.handling.spread_direction(Basis.IDENTITY,
		base.spread_hip_deg * 0.8, 1, _player.get_multiplayer_authority(), 0)
	assert_almost_eq(directions[1], expected, 0.000001)
	assert_eq(_player.weapon.ammo_in_mag, base.mag_size - 1)


func test_models_use_named_mounts_and_private_viewmodel_materials() -> void:
	for name: String in AttachmentCommand.SLOT_NAMES:
		assert_false(_command("equip " + name).begins_with("Error"))
	var model: Node3D = _player.ads_view.model
	for attachment: AttachmentData in _player.weapon.attachments.items():
		var mount: Node = model.find_child(String(attachment.mount_name()), true, false)
		var child: Node3D = mount.get_node("Attachment_" + String(attachment.id).trim_prefix("test_")) as Node3D
		assert_not_null(child)
		var mesh: MeshInstance3D = child.get_node("Visual") as MeshInstance3D
		var material: BaseMaterial3D = mesh.get_active_material(0) as BaseMaterial3D
		assert_true(material.use_fov_override)
		assert_true(material.no_depth_test)
		assert_eq(material.fov_override, _player.ads_view.rig.config.fov)
		_player.ads_view.apply_ads(0.5)
		assert_eq(mesh.transparency, 0.5)


func test_repeated_model_replacement_preserves_model_and_node_count() -> void:
	_command("equip muzzle")
	var nodes: int = get_tree().get_node_count()
	var model: Node3D = _player.ads_view.model
	for repeat: int in range(60):
		assert_false(_command("equip muzzle").begins_with("Error"))
		assert_eq(_player.ads_view.model, model)
		assert_eq(get_tree().get_node_count(), nodes)
	_command("remove muzzle")
	assert_eq(get_tree().get_node_count(), nodes - 2)


func test_equipping_preserves_bloom_recoil_ads_and_simulation_ticks() -> void:
	var handling: WeaponHandling = _player.weapon_hitscan.handling
	assert_true(handling.advance(100, 60))
	handling.apply_shot(100, 1)
	var recoil: Vector2 = handling.recoil_deg
	var bloom: float = handling.bloom_deg
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 100
	inp.buttons = PlayerInput.BTN_AIM
	_player.ads.simulate(inp, 1.0)
	_player.ads.update_visuals(1.0)
	assert_eq(_player.ads.fraction, 1.0)
	_command("equip sight")
	assert_eq(handling.recoil_deg, recoil)
	assert_eq(handling.bloom_deg, bloom)
	assert_false(handling.advance(100, 60))
	assert_eq(_player.ads.fraction, 1.0)
	assert_eq(_player.ads.visual_fraction, 1.0)
	assert_lt(handling.spread_degrees(true, PlayerStance.STAND, 0.0),
		handling.spread_degrees(false, PlayerStance.STAND, 0.0))


func test_switch_round_trip_retains_attachments_and_updates_ads_data() -> void:
	_command("equip grip")
	var primary: Weapon = _player.weapon
	var model: Node3D = _player.ads_view.model
	var expected: float = primary.data.spread_hip_deg
	var inp: PlayerInput = PlayerInput.new()
	inp.tick = 0
	inp.weapon_slot = Loadout.Slot.SECONDARY
	_player.inventory.simulate(inp)
	inp.weapon_slot = 0
	for tick: int in range(1, 121):
		inp.tick = tick
		_player.inventory.simulate(inp)
	assert_eq(_player.inventory.active_slot, Loadout.Slot.SECONDARY)
	assert_eq(_player.weapon.attachments.items().size(), 0)
	inp.tick = 121
	inp.weapon_slot = Loadout.Slot.PRIMARY
	_player.inventory.simulate(inp)
	inp.weapon_slot = 0
	for tick: int in range(122, 241):
		inp.tick = tick
		_player.inventory.simulate(inp)
	assert_eq(_player.weapon, primary)
	assert_eq(_player.ads_view.model, model)
	assert_eq(primary.attachments.items().size(), 1)
	assert_eq(_player.weapon_hitscan.handling.spread_degrees(false, PlayerStance.STAND, 0.0), expected)


func test_other_players_and_shared_profile_are_unchanged() -> void:
	var other: Player = (load("res://src/player/player.tscn") as PackedScene).instantiate() as Player
	other.is_local_player = false
	add_child_autofree(other)
	var original: WeaponData = other.weapon.data
	var spread: float = original.spread_hip_deg
	assert_true(_player.weapon.attachments.equip(AttachmentCommand.PROFILES["grip"]))
	assert_eq(original.spread_hip_deg, spread)
	assert_eq(other.weapon.data, original)
	assert_eq(other.weapon.attachments.items().size(), 0)
	assert_null(other.ads_view.model)


func test_command_errors_do_not_change_loadout_or_ammo() -> void:
	for text: String in ["", "equip", "equip unknown", "remove unknown", "bad grip", "list a b"]:
		var output: String = _command(text)
		assert_true(output.begins_with("Error") or output.begins_with("Usage"))
	_player.health_component.apply_damage(1000.0)
	assert_has(_command("equip grip"), "Error")
	assert_eq(_player.weapon.attachments.items().size(), 0)
	assert_eq(_player.weapon.ammo_in_mag, _player.weapon.data.mag_size)


func test_command_rejects_missing_player_busy_inventory_and_melee() -> void:
	Game.debug.erase("local_health_component")
	assert_has(_command("equip grip"), "no local player")
	Game.debug["local_health_component"] = _player.health_component
	_player.inventory.phase = Inventory.Phase.DRAWING
	assert_has(_command("equip grip"), "inventory is busy")
	_player.inventory.phase = Inventory.Phase.READY
	_player.equipment.melee.busy = true
	assert_has(_command("equip grip"), "weapon unavailable")
	_player.equipment.melee.busy = false
	assert_eq(_player.weapon.attachments.items().size(), 0)


func test_source_scene_is_unchanged_and_missing_mount_is_safe() -> void:
	_command("equip muzzle")
	var fresh: Node = (load("res://src/weapons/temporary_viewmodel.tscn") as PackedScene).instantiate()
	assert_null(fresh.find_child("Attachment_muzzle", true, false))
	fresh.free()
	var empty: Node3D = Node3D.new()
	var view: AttachmentView = AttachmentView.new()
	view.apply(empty, [AttachmentCommand.PROFILES["grip"]], _player.ads_view.rig, ViewmodelRig.DEFAULT_CONFIG)
	assert_eq(empty.get_child_count(), 0)
	empty.free()
