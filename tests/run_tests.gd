extends SceneTree
## Minimal headless test runner. From the project folder:
##   godot --headless --path . -s res://tests/run_tests.gd
## Optional: -- --filter=genetics  (only files whose name contains the text)
## Exits with code 1 if any test fails.

const TEST_DIR := "res://tests/unit"


func _initialize() -> void:
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")

	var total := 0
	var failed := 0
	var files := Array(DirAccess.get_files_at(TEST_DIR))
	files.sort()
	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		if filter != "" and not file.contains(filter):
			continue
		var script: GDScript = load(TEST_DIR.path_join(file))
		if script == null:
			print("FAIL  %s: could not load (parse error?)" % file)
			failed += 1
			continue
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			var tc = script.new()
			if tc.has_method("before_each"):
				tc.before_each()
			tc.call(name)
			if tc.assertions == 0:
				tc.failures.append("no assertions ran (did the test hit a script error?)")
			if tc.failures.is_empty():
				print("ok    %s :: %s" % [file.get_basename(), name])
			else:
				failed += 1
				print("FAIL  %s :: %s" % [file.get_basename(), name])
				for f in tc.failures:
					print("        - " + f)

	print("\n%d tests, %d passed, %d failed" % [total, total - failed, failed])
	quit(1 if failed > 0 else 0)
