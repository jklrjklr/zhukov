extends SceneTree
## Headless audio coverage test:
##   gd --headless -s res://tools/audio_coverage.gd
## Collects every slot name used in Sfx.play/play_ui/hold/music/ambience calls under
## res://scripts (string literals) plus the shared slot list in docs/slice_spec.md and
## prints MISSING for any slot without a file. Exit code 1 if anything is missing.

const EXTRA := [ # loops / music slots not present as call literals
	"amb_wind", "amb_insects", "music_calm", "music_combat", "music_extract", "upload_loop", "pelican",
]
const EXTS := ["ogg", "wav"]
const MUSIC_STATES := ["calm", "combat", "extract", "off"]


func _init() -> void:
	var slots := {} # name -> source
	var re_call := RegEx.new()
	re_call.compile("Sfx\\.(play|play_ui|hold)\\(([^\\n]*)")
	var re_str := RegEx.new()
	re_str.compile("\"([a-z][a-z0-9_]*)\"")
	var re_amb := RegEx.new()
	re_amb.compile("Sfx\\.ambience\\(([^)]*)\\)")
	for path in _gd_files("res://scripts"):
		var text := FileAccess.get_file_as_string(path)
		for line in text.split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for m in re_call.search_all(line):
				var kind := m.get_string(1)
				var args := m.get_string(2)
				var strs := re_str.search_all(args)
				if kind == "hold":
					# hold(key, name, ...): the slot is the 2nd string-literal argument, or the
					# only one when the key is built dynamically (str(...)).
					var names: Array = []
					for sm in strs:
						names.append(sm.get_string(1))
					if names.size() >= 2:
						_add(slots, names[1], path)
					elif names.size() == 1 and not args.begins_with("\""):
						_add(slots, names[0], path)
				else:
					# every literal that is the first argument or in a ternary of the first argument
					for sm in re_str.search_all(_first_arg(args)):
						_add(slots, sm.get_string(1), path)
			for m in re_amb.search_all(line):
				for sm in re_str.search_all(m.get_string(1)):
					_add(slots, sm.get_string(1), path)
		# slot names passed through other variables (e.g. stats.shot_sound = "rifle_shot")
		for m in RegEx.create_from_string("shot_sound[^=\\n]*=\\s*\"([a-z0-9_]+)\"").search_all(text):
			_add(slots, m.get_string(1), path)
	for n in EXTRA:
		_add(slots, n, "required loop")
	for n in _spec_slots():
		_add(slots, n, "docs/slice_spec.md")
	var missing := 0
	var names := slots.keys()
	names.sort()
	for n in names:
		if not _has_file(n):
			missing += 1
			print("MISSING: %s (from %s)" % [n, slots[n]])
	print("audio coverage: %d slots, %d missing" % [names.size(), missing])
	quit(1 if missing > 0 else 0)


func _first_arg(args: String) -> String:
	# text up to the first top-level comma
	var depth := 0
	var in_str := false
	for i in args.length():
		var c := args[i]
		if c == "\"":
			in_str = not in_str
		elif not in_str:
			if c == "(":
				depth += 1
			elif c == ")":
				if depth == 0:
					return args.substr(0, i)
				depth -= 1
			elif c == "," and depth == 0:
				return args.substr(0, i)
	return args


func _add(slots: Dictionary, n: String, src: String) -> void:
	if n in MUSIC_STATES or n.is_empty():
		return
	if not slots.has(n):
		slots[n] = src.get_file()


func _has_file(n: String) -> bool:
	for ext in EXTS:
		if FileAccess.file_exists("res://audio/%s.%s" % [n, ext]):
			return true
	return false


func _gd_files(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_gd_files(dir.path_join(sub)))
	return out


## Parses the "Shared sound slot names" section of the spec.
func _spec_slots() -> Array:
	var out: Array = []
	var text := FileAccess.get_file_as_string("res://docs/slice_spec.md")
	var i := text.find("## Shared sound slot names")
	if i == -1:
		push_warning("slice_spec.md has no shared slot list")
		return out
	var section := text.substr(i)
	var nxt := section.find("\n## ", 5)
	if nxt != -1:
		section = section.substr(0, nxt)
	var skip := ["pelican", "upload_loop"] # engine loop names handled by EXTRA
	for line in section.split("\n").slice(1):
		var colon := line.find(":")
		if colon == -1:
			continue
		var body := line.substr(colon + 1)
		body = RegEx.create_from_string("\\([^)]*\\)").sub(body, "", true) # drop "(idle, small)" notes
		for tok in body.split(","):
			var n := tok.strip_edges().trim_suffix(".")
			if RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(n):
				out.append(n)
	return out
