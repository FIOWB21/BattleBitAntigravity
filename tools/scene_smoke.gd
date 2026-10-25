extends SceneTree


class SmokeErrorTracker extends Logger:
	var error_count: int = 0

	func _log_error(
		_function: String,
		_file: String,
		_line: int,
		_code: String,
		_rationale: String,
		_editor_notify: bool,
		_error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		error_count += 1


func _initialize() -> void:
	var tracker: SmokeErrorTracker = SmokeErrorTracker.new()
	OS.add_logger(tracker)
	var failed: int = 0
	var scenes: Array[String] = []
	scenes.append_array(_find_scenes("res://src"))
	scenes.append_array(_find_scenes("res://tests"))
	for path: String in scenes:
		var errs_before: int = tracker.error_count
		var res: Resource = load(path)
		if res == null or not (res is PackedScene):
			printerr("SMOKE FAIL load: ", path)
			failed += 1
			continue
		var inst: Node = (res as PackedScene).instantiate()
		if inst == null or tracker.error_count > errs_before:
			printerr("SMOKE FAIL instantiate: ", path)
			failed += 1
			if inst != null:
				inst.free()
		else:
			inst.free()
	OS.remove_logger(tracker)
	print("SMOKE done, failed=", failed)
	quit(1 if failed > 0 else 0)


func _find_scenes(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		return out
	for d: String in da.get_directories():
		out.append_array(_find_scenes(dir_path + "/" + d))
	for f: String in da.get_files():
		if f.ends_with(".tscn"):
			out.append(dir_path + "/" + f)
	return out
