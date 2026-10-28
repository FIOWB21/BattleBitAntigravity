# Owner-only input and presentation. Network movement begins in its own step.
class_name LocalPlayerController
extends Node

var player: Player
var hud: HUD
var enabled: bool = false


func setup(actor: Player) -> void:
	player = actor
	enabled = actor.is_local_player and not Game.is_dedicated
	actor.camera.current = enabled
	actor.camera.top_level = enabled
	if not enabled:
		return
	Game.debug["local_health_component"] = actor.health_component
	actor.capture_mouse()
	actor.update_camera_visuals(0.0)
	if actor.network_owner_id != 0:
		hud = preload("res://src/ui/hud/hud.tscn").instantiate() as HUD
		add_child(hud)
		hud.bind_player(actor)


func handle_event(event: InputEvent) -> void:
	if enabled:
		player.handle_input_event(event)


func physics_step(delta: float) -> void:
	if not enabled or player.network_owner_id != 0:
		return
	var inp: PlayerInput = player.input_reader.read_input()
	player.server_sim.simulate(inp, delta)
	Game.debug["player_position"] = player.global_position


func present(delta: float) -> void:
	if enabled:
		player.update_camera_visuals(delta)
