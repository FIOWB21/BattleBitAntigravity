class_name ServerPlayerSim
extends Node

var player: Player
var enabled: bool = false


func setup(actor: Player) -> void:
	player = actor
	enabled = multiplayer.is_server()
	process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED


func simulate(inp: PlayerInput, delta: float) -> void:
	if enabled and multiplayer.is_server():
		player.step_simulation(inp, delta)
