class_name GadgetTestCase
extends GutTest


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func make_world() -> Node3D:
	var world: Node3D = Node3D.new()
	add_child_autofree(world)
	world.position = Vector3(6000.0, 0.0, 6000.0)
	return world


func make_target(world: Node3D, at: Vector3) -> HealthComponent:
	var entity: Node3D = Node3D.new()
	entity.position = at
	var health: HealthComponent = HealthComponent.new()
	health.name = "Health"
	entity.add_child(health)
	var zone: HitboxZone = HitboxZone.new()
	zone.name = "Zone"
	zone.configure(HitboxZone.TORSO, 1.0, health)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.2
	collision.shape = shape
	zone.add_child(collision)
	entity.add_child(zone)
	world.add_child(entity)
	return health


func zone_of(health: HealthComponent) -> HitboxZone:
	return health.get_parent().get_node("Zone") as HitboxZone


func make_box(world: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = at
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	return body


func make_player(world: Node3D, class_id: String, profile: GadgetData) -> Player:
	var player: Player = load("res://src/player/player.tscn").instantiate() as Player
	player.is_local_player = false
	player.class_data = load("res://src/classes/data/" + class_id + ".tres") as ClassData
	var inventory: Inventory = player.get_node("Inventory") as Inventory
	inventory.loadout = inventory.loadout.duplicate() as Loadout
	inventory.loadout.gadget_1 = profile
	if class_id == "support":
		inventory.loadout.primary = load("res://src/weapons/data/lmg.tres") as WeaponData
		(player.get_node("Weapon") as Weapon).data = inventory.loadout.primary
	elif class_id == "engineer":
		inventory.loadout.primary = load("res://src/weapons/data/smg.tres") as WeaponData
		(player.get_node("Weapon") as Weapon).data = inventory.loadout.primary
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.equipment.projectiles.system.set_physics_process(false)
	return player


func client_api(world: Node3D) -> ENetMultiplayerPeer:
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 9), OK)
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, world.get_path())
	return peer


func restore_api(world: Node3D, peer: ENetMultiplayerPeer) -> void:
	get_tree().set_multiplayer(null, world.get_path())
	peer.close()
