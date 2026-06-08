extends SceneTree


func _init() -> void:
	var passed := 0
	var failed := 0

	var test_scripts: Array[String] = []
	var dir := DirAccess.open("res://tests")
	if dir:
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.begins_with("test_") and name.ends_with(".gd"):
				test_scripts.append("res://tests/" + name)
			name = dir.get_next()
		dir.list_dir_end()

	for path in test_scripts:
		var script: GDScript = load(path)
		# load() returns a GDScript object even when compilation failed, so a
		# truthiness check is not enough — verify it can actually instantiate.
		if script == null or not script.can_instantiate():
			print("FAIL  ", path.get_file(), " (failed to load/compile)")
			failed += 1
			continue
		var suite: Object = script.new()
		if suite == null:
			print("FAIL  ", path.get_file(), " (could not instantiate suite)")
			failed += 1
			continue
		for method in suite.get_method_list():
			if not method["name"].begins_with("test_"):
				continue
			var test_name: String = path.get_file() + "::" + method["name"]
			suite.call(method["name"])
			print("PASS  ", test_name)
			passed += 1

	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
