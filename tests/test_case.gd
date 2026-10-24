class_name TestCase
extends RefCounted
## Base class for tests. Every method starting with "test_" is run by tests/run_tests.gd.
## Autoloads (EventBus, DataRegistry, GameState...) are available.

var failures: Array[String] = []


func before_each() -> void:
	pass


func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		failures.append(msg)


func assert_false(cond: bool, msg: String = "expected false") -> void:
	assert_true(not cond, msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual != expected:
		failures.append("%s expected %s, got %s" % [msg, str(expected), str(actual)])


func assert_near(actual: float, expected: float, tolerance: float = 1e-4, msg: String = "") -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s expected %f ± %f, got %f" % [msg, expected, tolerance, actual])


func assert_not_null(v: Variant, msg: String = "expected non-null") -> void:
	assert_true(v != null, msg)
