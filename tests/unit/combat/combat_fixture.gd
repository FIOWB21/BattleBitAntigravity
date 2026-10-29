extends GutTest

var loader: MapLoader
var players: NetworkPlayers
var actor: Player
var old_tick: int
var old_dedicated: bool


func before_all() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
	old_tick = Net.tick
	old_dedicated = Game.is_dedicated
	Net.tick = 100
	Game.is_dedicated = true
	loader = MapLoader.new()
	add_child(loader)
	assert_eq(loader.load_map("testbed"), OK)
	players = loader.players
	players._slots[42] = 0
	actor = players._spawn_player({"peer_id": 42, "pose": loader.spawn_pose}) as Player
	players._container.add_child(actor)
	actor.life.rules = actor.life.rules.duplicate() as MatchRules
	_freeze(loader)


func after_each() -> void:
	loader.free()
	Net.tick = old_tick
	Game.is_dedicated = old_dedicated
	Game.set_state(Game.State.MENU)


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_freeze(child)


func _kill(source: int = 1, zone: int = HitboxZone.TORSO) -> void:
	actor.life.rules.downed_enabled = false
	(actor.health_component as HealthComponent).apply_damage(1000.0, source, zone, &"sample_ar", Vector3.FORWARD)
