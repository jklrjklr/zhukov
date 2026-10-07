extends SceneTree
## Contact sheet of baked sprite clips (top-down, as in game), cropped clips placed at their
## offset, with the gun anchor marked:
##   godot --headless --path . --script res://tools/sheet_preview.gd -- out.png <skin> <clip>...
const CELL := 112


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var skin: String = args[1]
	var clips: Array = args.slice(2)
	var maxn := 1
	var rows := []
	for c in clips:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://art/sprites/%s/%s.png" % [skin, c]))
		var jp := "res://art/sprites/%s/%s.json" % [skin, c]
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(jp)) if FileAccess.file_exists(jp) else {}
		var n: int = meta.get("frames_n", img.get_width() / img.get_height())
		maxn = maxi(maxn, n)
		rows.append([img, meta, n])
	var out := Image.create(CELL * maxn, CELL * rows.size(), false, Image.FORMAT_RGBA8)
	out.fill(Color("22382a"))
	for r in rows.size():
		var img: Image = rows[r][0]
		var meta: Dictionary = rows[r][1]
		var n: int = rows[r][2]
		var fw := img.get_width() / n
		var fh := img.get_height()
		var off := Vector2(-fw / 2.0, -fh / 2.0)
		if meta.has("rect"):
			off = Vector2(meta.rect[0], meta.rect[1]) - Vector2(meta.frame, meta.frame) / 2.0
		for i in n:
			var c := Vector2(i * CELL + CELL / 2.0, r * CELL + CELL / 2.0)
			var dst := Vector2i((c + off).round())
			var src := Rect2i(i * fw, 0, fw, fh)
			var clip := Rect2i(dst, src.size).intersection(Rect2i(i * CELL, r * CELL, CELL, CELL))
			out.blend_rect(img, Rect2i(src.position + clip.position - dst, clip.size), clip.position)
			var fr: Array = meta.get("frames", [])
			if i < fr.size():
				var g := c + Vector2(fr[i][0], fr[i][1])
				for k in 14:
					var p := Vector2i(g + Vector2(0, -k))
					if Rect2i(0, 0, out.get_width(), out.get_height()).has_point(p):
						out.set_pixelv(p, Color(1, 0.2, 0.2) if k > 2 else Color.YELLOW)
	out.resize(out.get_width() * 2, out.get_height() * 2, Image.INTERPOLATE_NEAREST)
	out.save_png(args[0])
	quit()
