# Owner-only input transmission and presentation.
class_name LocalPlayerController
extends Node

var player: Player
var hud: HUD
var enabled: bool = false
var history: InputHistory = InputHistory.new()
var prediction: Prediction = Prediction.new()
var delay: PacketDelay
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
		if not multiplayer.is_server():
			prediction.configure(preload("res://src/net/default_prediction.tres"))
			delay = PacketDelay.new()
			delay.configure(Net.config.input_history_count * InputCodec.FRAME_BYTES)
			delay.packet_delivered.connect(_transmit_input)
			add_child(delay)
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
		if not multiplayer.is_server():
			prediction.reconcile(player, delta)
		_send_input(delta)
	Game.debug["player_position"] = player.global_position
	Game.debug["reconciliations"] = prediction.reconciliations
	Game.debug["prediction_error"] = prediction.last_error
	Game.debug["prediction_teleports"] = prediction.hard_corrections


func _send_input(delta: float) -> void:
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
		history.latest_into(_input)
		prediction.predict(player, _input, delta)
		delay.submit(history.packet)


func _transmit_input(packet: PackedByteArray, _extra: PackedByteArray) -> void:
	if Net.is_connected and is_instance_valid(player):
		player.server_sim.submit_input.rpc_id(Net.SERVER_ID, packet)


func present(delta: float) -> void:
	if enabled:
		prediction.advance_visual(delta)
		player.update_camera_visuals(delta)


func _exit_tree() -> void:
	if player != null and player.is_local_player:
		Game.debug["reconciliations"] = 0
		Game.debug["prediction_error"] = 0.0
		Game.debug["prediction_teleports"] = 0
