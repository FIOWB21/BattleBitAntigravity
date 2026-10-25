extends SceneTree


class ErrorTracker extends Logger:
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


var _tracker: ErrorTracker = ErrorTracker.new()
var _total_scripts: int = 0
var _total_tests: int = 0
var _total_asserts: int = 0
var _failed_tests: int = 0


func _initialize() -> void:
	OS.add_logger(_tracker)
	var files: Array[String] = _find_test_files(_get_test_dir())
	files.sort()
	for path: String in files:
		await _run_script(path)
	OS.remove_logger(_tracker)
	print(
		"TESTS done: scripts=", _total_scripts,
		" tests=", _total_tests,
		" asserts=", _total_asserts,
		" failed=", _failed_tests
	)
	quit(1 if _failed_tests > 0 else 0)


func _get_test_dir() -> String:
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("-gdir="):
			return arg.trim_prefix("-gdir=")
	return "res://tests"


func _find_test_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		return out
	for d: String in da.get_directories():
		out.append_array(_find_test_files(dir_path + "/" + d))
	for f: String in da.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
	return out


func _run_script(path: String) -> void:
	_total_scripts += 1
	var errs_before: int = _tracker.error_count
	var res: Resource = load(path)
	if res == null or not (res is GDScript) or not (res as GDScript).can_instantiate():
		printerr("TEST FAIL load: ", path)
		_failed_tests += 1
		return
	if _tracker.error_count > errs_before:
		_failed_tests += 1
		return
	var script: GDScript = res as GDScript
	var inst: Object = script.new()
	if inst is Node:
		root.add_child(inst as Node)
	if inst.has_method("before_all"):
		await inst.call("before_all")
	for method_name: String in _get_test_methods(script):
		await _run_method(path, script, inst, method_name)
	if inst.has_method("after_all"):
		await inst.call("after_all")
	_cleanup_instance(inst)


func _get_test_methods(script: GDScript) -> Array[String]:
	var methods: Array[String] = []
	for m: Dictionary in script.get_script_method_list():
		var name_str: String = String(m.get("name", ""))
		if name_str.begins_with("test_"):
			methods.append(name_str)
	methods.sort()
	return methods


func _run_method(path: String, script: GDScript, inst: Object, method_name: String) -> void:
	_total_tests += 1
	if inst is GutTest:
		(inst as GutTest).reset_counts()
	var errs_before: int = _tracker.error_count
	if inst.has_method("before_each"):
		await inst.call("before_each")
	await inst.call(method_name)
	if inst.has_method("after_each"):
		await inst.call("after_each")
	var gut_asserts: int = 0
	var gut_fails: int = 0
	if inst is GutTest:
		var gut_inst: GutTest = inst as GutTest
		gut_asserts = gut_inst.get_assert_count()
		gut_fails = gut_inst.get_fail_count()
		gut_inst.cleanup_autofree()
	var builtin_asserts: int = _count_builtin_asserts(script.source_code, method_name)
	var logger_errs: int = _tracker.error_count - errs_before
	_total_asserts += gut_asserts + maxi(builtin_asserts, logger_errs)
	if gut_fails > 0 or logger_errs > 0:
		_failed_tests += 1
		printerr("FAIL: ", path, "::", method_name)
	else:
		print("PASS: ", path, "::", method_name)


func _count_builtin_asserts(source: String, method_name: String) -> int:
	var count: int = 0
	var in_method: bool = false
	var header_prefix: String = "func " + method_name + "("
	for line: String in source.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("func "):
			in_method = trimmed.begins_with(header_prefix)
			continue
		if in_method and not trimmed.begins_with("#"):
			if trimmed.begins_with("assert(") or trimmed.begins_with("assert ("):
				count += 1
	return count


func _cleanup_instance(inst: Object) -> void:
	if inst is Node and is_instance_valid(inst):
		var node: Node = inst as Node
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	elif not (inst is RefCounted) and is_instance_valid(inst):
		inst.free()
