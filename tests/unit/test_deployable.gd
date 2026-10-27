extends GutTest


func _world() -> Node3D:
	var world: Node3D = Node3D.new()
	add_child_autofree(world)
	return world


func _scene(valid_type: bool = true) -> PackedScene:
	var node: Node3D = Deployable.new() if valid_type else Node3D.new()
	var scene: PackedScene = PackedScene.new()
	assert_eq(scene.pack(node), OK)
	node.free()
	return scene


func _ctx(world: Node3D, tick: int = 10) -> GadgetContext:
	var ctx: GadgetContext = GadgetContext.new()
	ctx.tick = tick
	ctx.source_id = 42
	ctx.spawn_parent = world
	ctx.spawn_transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(2.0, 3.0, 4.0))
	return ctx


func _gadget(world: Node3D, scene: PackedScene) -> Gadget:
	var gadget: Gadget = Gadget.new()
	gadget.data = load("res://src/gadgets/data/base_gadget.tres").duplicate() as GadgetData
	gadget.data.deployable_scene = scene
	world.add_child(gadget)
	return gadget


func test_server_spawns_with_source_tick_and_world_transform() -> void:
	var world: Node3D = _world()
	world.position = Vector3(-5.0, 2.0, 10.0)
	world.rotation.y = 1.2
	world.scale = Vector3.ONE * 2.0
	var ctx: GadgetContext = _ctx(world)
	var object: Deployable = Deployable.spawn(_scene(), ctx)
	assert_not_null(object)
	assert_eq(object.get_parent(), world)
	assert_eq(object.source_id, 42)
	assert_eq(object.spawn_tick, 10)
	assert_true(object.global_transform.is_equal_approx(ctx.spawn_transform))
	assert_eq(object.get_multiplayer_authority(), 1)


func test_gadget_creates_one_object_and_spends_one_charge() -> void:
	var world: Node3D = _world()
	var gadget: Gadget = _gadget(world, _scene())
	var created: Array[Deployable] = []
	gadget.deployable_created.connect(func(object: Deployable) -> void: created.append(object))
	assert_true(gadget.use(_ctx(world)))
	assert_false(gadget.use(_ctx(world)))
	assert_eq(created.size(), 1)
	assert_eq(world.get_child_count(), 2)
	assert_eq(gadget.charges, 1)
	assert_eq(created[0].source_id, 42)


func test_invalid_scene_fails_without_spending_charge_or_cooldown() -> void:
	var world: Node3D = _world()
	var gadget: Gadget = _gadget(world, _scene(false))
	assert_false(gadget.use(_ctx(world)))
	assert_eq(gadget.charges, 2)
	assert_eq(gadget.next_use_tick, 0)
	assert_eq(world.get_child_count(), 1)
	gadget.data.deployable_scene = _scene()
	assert_true(gadget.use(_ctx(world)))


func test_invalid_contexts_and_unpacked_scene_do_not_spawn() -> void:
	var world: Node3D = _world()
	var scene: PackedScene = _scene()
	assert_null(Deployable.spawn(null, _ctx(world)))
	assert_null(Deployable.spawn(PackedScene.new(), _ctx(world)))
	assert_null(Deployable.spawn(scene, null))
	assert_null(Deployable.spawn(scene, _ctx(world, -1)))
	assert_null(Deployable.spawn(scene, _ctx(null)))
	var detached: Node3D = Node3D.new()
	assert_null(Deployable.spawn(scene, _ctx(detached)))
	detached.free()
	var ctx: GadgetContext = _ctx(world)
	ctx.spawn_transform.origin.x = NAN
	assert_null(Deployable.spawn(scene, ctx))
	assert_eq(world.get_child_count(), 0)


func test_server_despawn_is_idempotent_and_emits_once() -> void:
	var object: Deployable = Deployable.spawn(_scene(), _ctx(_world()))
	var events: Array[int] = [0]
	object.despawned.connect(func() -> void: events[0] += 1)
	assert_true(object.despawn())
	assert_false(object.despawn())
	assert_true(object.is_queued_for_deletion())
	assert_eq(events[0], 1)


func test_client_cannot_use_reload_advance_setup_spawn_or_despawn() -> void:
	var world: Node3D = _world()
	var gadget: Gadget = _gadget(world, _scene())
	assert_true(gadget.use(_ctx(world, 0)))
	assert_true(gadget.reload(1))
	var object: Deployable = world.get_child(1) as Deployable
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 9), OK)
	api.multiplayer_peer = peer
	var path: NodePath = world.get_path()
	get_tree().set_multiplayer(api, path)
	assert_false(Game.is_server_or_offline(world.multiplayer))
	gadget.simulate(1000)
	assert_false(gadget.can_use())
	assert_false(gadget.use(_ctx(world, 1000)))
	assert_false(gadget.reload(1000))
	assert_false(gadget.setup(gadget.data))
	assert_null(Deployable.spawn(_scene(), _ctx(world)))
	assert_false(object.despawn())
	assert_eq(gadget.charges, 1)
	assert_eq(gadget.reload_end_tick, 91)
	assert_eq(world.get_child_count(), 2)
	assert_false(object.is_queued_for_deletion())
	get_tree().set_multiplayer(null, path)
	peer.close()
	gadget.simulate(91)
	assert_eq(gadget.charges, 2)


func test_global_server_flag_cannot_bypass_client_api() -> void:
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	assert_true(Game.is_server_or_offline(api))
	assert_true(Game.is_server_or_offline())
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 9), OK)
	api.multiplayer_peer = peer
	var previous: bool = Game.is_server
	Game.is_server = true
	assert_false(Game.is_server_or_offline(api))
	Game.is_server = previous
	peer.close()
