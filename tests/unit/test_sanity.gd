extends GutTest


func test_sanity_arithmetic() -> void:
	var sum_val: int = 2 + 2
	assert_eq(sum_val, 4, "2 + 2 must equal 4")
	assert_true(sum_val > 0, "sum must be positive")
	assert(sum_val == 4, "built-in assert sanity check")


func test_sanity_vectors() -> void:
	var dir: Vector3 = Vector3(3.0, 0.0, 4.0).normalized()
	assert_almost_eq(dir.length(), 1.0, 0.0001, "normalized vector length must be 1.0")
