extends SceneTree
## Minimal headless test runner. Usage (from the project folder):
##   godot --headless --path . -s res://tests/run_tests.gd [-- filter]
## Finds tests/**/test_*.gd, runs each test_* method, exits non-zero on failure.

const TEST_ROOT := "res://tests"


func _initialize() -> void:
	# Wait one frame so autoloads finish _ready().
	await process_frame
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		filter = args[0]

	var passed := 0
	var failed := 0
	for path in _find_tests(TEST_ROOT):
		if filter != "" and not path.contains(filter):
			continue
		var script: GDScript = load(path)
		# A file that fails to compile has no methods; count it instead of silently skipping it.
		if script == null or not script.can_instantiate():
			failed += 1
			print("FAIL %s: does not compile" % path.get_file())
			continue
		for method in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			var test: TestCase = script.new()
			test.before_each()
			await test.call(name)
			if test.failures.is_empty():
				passed += 1
			else:
				failed += 1
				print("FAIL %s::%s" % [path.get_file(), name])
				for f in test.failures:
					print("     ", f)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _find_tests(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_find_tests(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			out.append(dir_path.path_join(file))
	return out
