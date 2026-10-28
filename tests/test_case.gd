extends RefCounted
## Base class for unit tests. Every method named test_* is run on a fresh
## instance by tests/run_tests.gd. A test with no assertions counts as a failure.

var failures: Array[String] = []
var assertions: int = 0


func _check(ok: bool, msg: String) -> bool:
	assertions += 1
	if not ok:
		failures.append(msg)
	return ok


func _label(msg: String) -> String:
	return "" if msg == "" else " (%s)" % msg


static func _equal(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return a == b
	return typeof(a) == typeof(b) and a == b


func assert_eq(actual, expected, msg: String = "") -> bool:
	return _check(_equal(actual, expected),
		"expected %s, got %s%s" % [str(expected), str(actual), _label(msg)])


func assert_ne(actual, unexpected, msg: String = "") -> bool:
	return _check(actual != unexpected, "did not expect %s%s" % [str(actual), _label(msg)])


func assert_true(cond: bool, msg: String = "") -> bool:
	return _check(cond, "expected true%s" % _label(msg))


func assert_false(cond: bool, msg: String = "") -> bool:
	return _check(not cond, "expected false%s" % _label(msg))


func assert_between(value, low, high, msg: String = "") -> bool:
	return _check(value >= low and value <= high,
		"expected %s to be between %s and %s%s" % [str(value), str(low), str(high), _label(msg)])


func assert_almost(actual: float, expected: float, epsilon: float = 0.0001, msg: String = "") -> bool:
	return _check(absf(actual - expected) <= epsilon,
		"expected ~%s, got %s%s" % [str(expected), str(actual), _label(msg)])


func assert_has(container, value, msg: String = "") -> bool:
	return _check(value in container, "expected %s to contain %s%s" % [str(container), str(value), _label(msg)])
