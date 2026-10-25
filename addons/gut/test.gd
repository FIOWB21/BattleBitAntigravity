class_name GutTest
extends Node

var _assert_count: int = 0
var _fail_count: int = 0
var _autofree_objects: Array[Variant] = []


func before_all() -> void:
	pass


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func after_all() -> void:
	pass


func reset_counts() -> void:
	_assert_count = 0
	_fail_count = 0


func get_assert_count() -> int:
	return _assert_count


func get_fail_count() -> int:
	return _fail_count


func autofree(obj: Variant) -> Variant:
	if obj != null:
		_autofree_objects.append(obj)
	return obj


func add_child_autofree(node: Node) -> Node:
	add_child(node)
	_autofree_objects.append(node)
	return node


func cleanup_autofree() -> void:
	for i: int in range(_autofree_objects.size() - 1, -1, -1):
		var obj: Variant = _autofree_objects[i]
		if obj is Node and is_instance_valid(obj):
			var node: Node = obj as Node
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
		elif obj is Object and not (obj is RefCounted) and is_instance_valid(obj):
			(obj as Object).free()
	_autofree_objects.clear()


func _record_assert(passed: bool, detail: String, msg: String) -> void:
	_assert_count += 1
	if not passed:
		_fail_count += 1
		var full_msg: String = detail if msg.is_empty() else detail + " (" + msg + ")"
		printerr("  ASSERT FAIL: ", full_msg)


func pass_test(msg: String = "") -> void:
	_record_assert(true, "pass_test", msg)


func fail_test(msg: String = "") -> void:
	_record_assert(false, "fail_test", msg)


func assert_true(cond: bool, msg: String = "") -> void:
	_record_assert(cond == true, "Expected true, got " + str(cond), msg)


func assert_false(cond: bool, msg: String = "") -> void:
	_record_assert(cond == false, "Expected false, got " + str(cond), msg)


func assert_eq(got: Variant, expected: Variant, msg: String = "") -> void:
	var passed: bool = got == expected
	_record_assert(passed, "Expected [" + str(expected) + "], got [" + str(got) + "]", msg)


func assert_ne(got: Variant, not_expected: Variant, msg: String = "") -> void:
	var passed: bool = got != not_expected
	_record_assert(passed, "Expected not [" + str(not_expected) + "], got [" + str(got) + "]", msg)


func _is_almost_eq(got: Variant, expected: Variant, tol: Variant) -> bool:
	if (got is float or got is int) and (expected is float or expected is int):
		return absf(float(got) - float(expected)) <= float(tol)
	if got is Vector2 and expected is Vector2:
		var g2: Vector2 = got
		var e2: Vector2 = expected
		var t2: Vector2 = tol if tol is Vector2 else Vector2(float(tol), float(tol))
		return absf(g2.x - e2.x) <= t2.x and absf(g2.y - e2.y) <= t2.y
	if got is Vector3 and expected is Vector3:
		var g3: Vector3 = got
		var e3: Vector3 = expected
		var t3: Vector3 = tol if tol is Vector3 else Vector3(float(tol), float(tol), float(tol))
		return absf(g3.x - e3.x) <= t3.x and absf(g3.y - e3.y) <= t3.y and absf(g3.z - e3.z) <= t3.z
	return got == expected


func assert_almost_eq(got: Variant, expected: Variant, error_interval: Variant, msg: String = "") -> void:
	var passed: bool = _is_almost_eq(got, expected, error_interval)
	var detail: String = "Expected [" + str(got) + "] ~= [" + str(expected) + "] +/- " + str(error_interval)
	_record_assert(passed, detail, msg)


func assert_almost_ne(got: Variant, not_expected: Variant, error_interval: Variant, msg: String = "") -> void:
	var passed: bool = not _is_almost_eq(got, not_expected, error_interval)
	var detail: String = "Expected [" + str(got) + "] !~= [" + str(not_expected) + "] +/- " + str(error_interval)
	_record_assert(passed, detail, msg)


func assert_gt(got: Variant, expected: Variant, msg: String = "") -> void:
	var passed: bool = float(got) > float(expected)
	_record_assert(passed, "Expected [" + str(got) + "] > [" + str(expected) + "]", msg)


func assert_lt(got: Variant, expected: Variant, msg: String = "") -> void:
	var passed: bool = float(got) < float(expected)
	_record_assert(passed, "Expected [" + str(got) + "] < [" + str(expected) + "]", msg)


func assert_gte(got: Variant, expected: Variant, msg: String = "") -> void:
	var passed: bool = float(got) >= float(expected)
	_record_assert(passed, "Expected [" + str(got) + "] >= [" + str(expected) + "]", msg)


func assert_lte(got: Variant, expected: Variant, msg: String = "") -> void:
	var passed: bool = float(got) <= float(expected)
	_record_assert(passed, "Expected [" + str(got) + "] <= [" + str(expected) + "]", msg)


func assert_between(got: Variant, expect_low: Variant, expect_high: Variant, msg: String = "") -> void:
	var val: float = float(got)
	var passed: bool = val >= float(expect_low) and val <= float(expect_high)
	var detail: String = "Expected [" + str(got) + "] between [" + str(expect_low) + "] and [" + str(expect_high) + "]"
	_record_assert(passed, detail, msg)


func assert_null(got: Variant, msg: String = "") -> void:
	_record_assert(got == null, "Expected null, got [" + str(got) + "]", msg)


func assert_not_null(got: Variant, msg: String = "") -> void:
	_record_assert(got != null, "Expected not null, got null", msg)


func assert_has(obj: Variant, element: Variant, msg: String = "") -> void:
	var passed: bool = false
	if obj is Array or obj is Dictionary or obj is String:
		passed = element in obj
	_record_assert(passed, "Expected [" + str(obj) + "] to contain [" + str(element) + "]", msg)


func assert_does_not_have(obj: Variant, element: Variant, msg: String = "") -> void:
	var passed: bool = false
	if obj is Array or obj is Dictionary or obj is String:
		passed = not (element in obj)
	_record_assert(passed, "Expected [" + str(obj) + "] not to contain [" + str(element) + "]", msg)
