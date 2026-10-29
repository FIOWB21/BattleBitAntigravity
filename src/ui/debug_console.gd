# Парсер и реестр команд отладочной консоли (name -> Callable).
class_name DebugConsole
extends RefCounted

signal command_executed(command_line: String, output: String)
signal god_toggled(enabled: bool)
signal noclip_toggled(enabled: bool)
signal damage_requested(amount: float)

const MIN_FPS: int = 0
const MIN_PING_MS: int = 0
const MIN_LOSS_PCT: float = 0.0
const MAX_LOSS_PCT: float = 100.0

var commands: Dictionary = {}
var history: Array[String] = []
var output_lines: Array[String] = []
var damage_target: Object = null


func _init() -> void:
	_register_builtin_commands()


func register_command(cmd_name: String, callback: Callable) -> void:
	var normalized: String = cmd_name.strip_edges().to_lower()
	if normalized.is_empty():
		return
	commands[normalized] = callback


func unregister_command(cmd_name: String) -> void:
	var normalized: String = cmd_name.strip_edges().to_lower()
	commands.erase(normalized)


func has_command(cmd_name: String) -> bool:
	var normalized: String = cmd_name.strip_edges().to_lower()
	return commands.has(normalized)


func parse_command(raw_line: String) -> Dictionary:
	var normalized_whitespace: String = raw_line.replace("\t", " ").strip_edges()
	if normalized_whitespace.is_empty():
		return {
			"name": "",
			"args": PackedStringArray(),
		}
	var tokens: PackedStringArray = normalized_whitespace.split(" ", false)
	var cmd_name: String = tokens[0].to_lower()
	var cmd_args: PackedStringArray = tokens.slice(1)
	return {
		"name": cmd_name,
		"args": cmd_args,
	}


func execute_command(raw_line: String) -> String:
	var parsed: Dictionary = parse_command(raw_line)
	var cmd_name: String = String(parsed["name"])
	var cmd_args: PackedStringArray = parsed["args"]
	if cmd_name.is_empty():
		return ""

	history.append(raw_line.strip_edges())
	if not commands.has(cmd_name):
		var unknown_msg: String = "Unknown command: %s. Type 'help' for a list of commands." % cmd_name
		_record_output(raw_line, unknown_msg)
		return unknown_msg

	var callback: Callable = commands[cmd_name]
	var result: Variant = callback.call(cmd_args)
	var output: String = str(result) if result != null else ""
	_record_output(raw_line, output)
	return output


func _record_output(raw_line: String, output: String) -> void:
	if not output.is_empty():
		output_lines.append(output)
	command_executed.emit(raw_line, output)


func _register_builtin_commands() -> void:
	register_command("help", _cmd_help)
	register_command("fps", _cmd_fps)
	register_command("net_sim", _cmd_net_sim)
	register_command("god", _cmd_god)
	register_command("noclip", _cmd_noclip)
	register_command("damage", _cmd_damage)
	register_command("attachment", AttachmentCommand.execute)


func _cmd_help(_args: PackedStringArray) -> String:
	var names: Array[String] = []
	for key: Variant in commands.keys():
		names.append(String(key))
	names.sort()
	var msg: String = "Available commands: " + ", ".join(names)
	Log.i(msg)
	return msg


func _cmd_fps(args: PackedStringArray) -> String:
	if args.size() != 1 or not args[0].is_valid_int():
		return "Usage: fps <n>"
	var target_fps: int = args[0].to_int()
	if target_fps < MIN_FPS:
		return "Error: fps must be >= 0"
	Engine.max_fps = target_fps
	Game.debug["max_fps"] = target_fps
	return "fps: max_fps set to %d" % target_fps


func _cmd_net_sim(args: PackedStringArray) -> String:
	if args.size() < 2 or args.size() > 5 or not args[0].is_valid_int() or not args[1].is_valid_float():
		return "Usage: net_sim <ping_ms> <loss_%> [jitter_ms] [duplicate_%] [reorder_%]"
	var ping_ms: int = args[0].to_int()
	var loss_pct: float = args[1].to_float()
	var cfg: NetSimConfig = NetSimConfig.new()
	cfg.rtt_ms = ping_ms
	cfg.loss_percent = loss_pct
	if args.size() > 2:
		if not args[2].is_valid_int():
			return "Error: jitter_ms must be an integer"
		cfg.jitter_ms = args[2].to_int()
	for index: int in range(3, args.size()):
		if not args[index].is_valid_float():
			return "Error: percentages must be finite numbers"
		if index == 3:
			cfg.duplicate_percent = args[index].to_float()
		else:
			cfg.reorder_percent = args[index].to_float()
	if not cfg.is_valid():
		return "Error: delays must be 0..2000 ms; percentages must be 0..100"
	Net.time_sync.configure_simulation(ping_ms, loss_pct, cfg.jitter_ms, cfg.duplicate_percent, cfg.reorder_percent)
	Game.debug["simulated_ping_ms"] = ping_ms
	Game.debug["loss_percent"] = loss_pct
	Game.debug["loss_pct"] = loss_pct
	Game.debug["loss"] = loss_pct
	return "net_sim: ping=%d ms, loss=%.1f%%, jitter=%d ms, duplicate=%.1f%%, reorder=%.1f%%" % [
		ping_ms, loss_pct, cfg.jitter_ms, cfg.duplicate_percent, cfg.reorder_percent]


func _cmd_god(args: PackedStringArray) -> String:
	var current: bool = bool(Game.debug.get("god", false))
	var next_val: bool = _resolve_toggle_arg(args, current)
	Game.debug["god"] = next_val
	god_toggled.emit(next_val)
	return "god: %s" % ("ON" if next_val else "OFF")


func _cmd_noclip(args: PackedStringArray) -> String:
	var current: bool = bool(Game.debug.get("noclip", false))
	var next_val: bool = _resolve_toggle_arg(args, current)
	Game.debug["noclip"] = next_val
	noclip_toggled.emit(next_val)
	return "noclip: %s" % ("ON" if next_val else "OFF")


func _resolve_toggle_arg(args: PackedStringArray, current: bool) -> bool:
	if args.is_empty():
		return not current
	var token: String = args[0].to_lower()
	if token == "1" or token == "true" or token == "on":
		return true
	if token == "0" or token == "false" or token == "off":
		return false
	return not current


func _cmd_damage(args: PackedStringArray) -> String:
	if args.size() != 1 or not args[0].is_valid_float():
		return "Usage: damage <n>"
	var amount: float = args[0].to_float()
	if amount <= 0.0:
		return "Error: damage must be > 0"
	damage_requested.emit(amount)
	var target: Object = _resolve_damage_target()
	if target != null and target.has_method("apply_damage"):
		target.call("apply_damage", amount)
		if target is HealthComponent:
			var hc: HealthComponent = target as HealthComponent
			return "damage: %.1f (health: %.1f/%.1f)" % [amount, hc.current, hc.max_health]
	return "damage: %.1f" % amount


func _resolve_damage_target() -> Object:
	if damage_target != null and is_instance_valid(damage_target):
		if damage_target.has_method("apply_damage"):
			return damage_target
		if damage_target is Node:
			var child_hc: Node = (damage_target as Node).get_node_or_null("HealthComponent")
			if child_hc != null:
				return child_hc
	var debug_hc: Variant = Game.debug.get("local_health_component", null)
	if debug_hc is Object and is_instance_valid(debug_hc):
		return debug_hc as Object
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop as SceneTree
		if tree.root != null:
			var player_node: Node = tree.root.find_child("Player", true, false)
			if player_node != null:
				var hc_node: Node = player_node.get_node_or_null("HealthComponent")
				if hc_node != null:
					return hc_node
	return null
