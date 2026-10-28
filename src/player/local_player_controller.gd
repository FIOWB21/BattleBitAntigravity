# Owner-only input transmission and presentation.
class_name LocalPlayerController
extends Node

var player: Player
var hud: HUD
var enabled: bool = false
var history: InputHistory = InputHistory.new()
var _input: PlayerInput = PlayerInput.new()
var _sent_tick: int = 0


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
		history.configure(Net.config.input_history_count)
		hud = preload("res://src/ui/hud/hud.tscn").instantiate() as HUD
		add_child(hud)
		hud.bind_player(actor)


func handle_event(event: InputEvent) -> void:
	if enabled:
		player.handle_input_event(event)


func physics_step(delta: float) -> void:
	if not enabled:
		return
	if player.network_owner_id == 0:
		player.input_reader.read_into(_input)
		player.server_sim.simulate(_input, delta)
	else:
		_send_input()
	Game.debug["player_position"] = player.global_position


func _send_input() -> void:
	if not Net.is_connected or (not multiplayer.is_server() and not Net.clock.is_synchronized):
		return
	player.input_reader.read_into(_input)
	_input.tick = maxi(_sent_tick + 1, Net.tick)
	if not history.push(_input):
		return
	_sent_tick = _input.tick
	if multiplayer.is_server():
		player.server_sim.receive_local(history.packet)
	else:
		player.server_sim.submit_input.rpc_id(Net.SERVER_ID, history.packet)


func present(delta: float) -> void:
	if enabled:
		player.update_camera_visuals(delta)
