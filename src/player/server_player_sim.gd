class_name ServerPlayerSim
extends Node

signal input_simulated(inp: PlayerInput)

var player: Player
var enabled: bool = false
var input_queue: ServerInputQueue = ServerInputQueue.new()
var simulated_ticks: int = 0


func setup(actor: Player) -> void:
	player = actor
	enabled = multiplayer.is_server()
	process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	if enabled and actor.network_owner_id != 0:
		input_queue.configure(Net.config, Engine.physics_ticks_per_second, actor.rotation.y)


func simulate(inp: PlayerInput, delta: float) -> void:
	if enabled and multiplayer.is_server():
		player.step_simulation(inp, delta)


func physics_step(delta: float) -> void:
	if not enabled or player.network_owner_id == 0 or not Net.is_connected:
		return
	var inp: PlayerInput = input_queue.consume(Net.tick)
	if inp != null:
		simulate(inp, delta)
		if player.equipment != null and player.equipment.combat != null:
			player.equipment.combat.physics_step()
		simulated_ticks += 1
		input_simulated.emit(inp)


func receive_local(packet: PackedByteArray) -> void:
	if enabled and multiplayer.is_server() and player.network_owner_id == Net.SERVER_ID:
		input_queue.receive(packet, Net.tick)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_input(packet: PackedByteArray) -> void:
	if not enabled or not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != player.network_owner_id or not Net.nicknames.has(sender):
		return
	input_queue.receive(packet, Net.tick)
