class_name BackpackLayout

# Parses the backpack notation string.
# Returns Array of rows; each row is Array[Vector2i] of (cols, rows) per compartment.
#
# Format: {(cols,rows),(cols,rows) | (cols,rows)}
#   ,  = side-by-side (horizontal, same row)
#   |  = stacked below (starts a new row)
static func parse(notation: String) -> Array:
	var result: Array = []
	var cleaned := notation.strip_edges().trim_prefix("{").trim_suffix("}")
	var row_strings := _split_ignoring_parens(cleaned, "|")
	for row_str: String in row_strings:
		var row: Array[Vector2i] = []
		var comp_strings := _split_ignoring_parens(row_str.strip_edges(), ",")
		for comp_str: String in comp_strings:
			var dim := _parse_dim(comp_str.strip_edges())
			if dim.x > 0 and dim.y > 0:
				row.append(dim)
		if not row.is_empty():
			result.append(row)
	return result

# Splits text by separator only when not inside parentheses.
static func _split_ignoring_parens(text: String, separator: String) -> Array:
	var parts: Array[String] = []
	var depth := 0
	var current := ""
	for i in text.length():
		var c := text[i]
		if c == "(":
			depth += 1
			current += c
		elif c == ")":
			depth -= 1
			current += c
		elif c == separator and depth == 0:
			parts.append(current)
			current = ""
		else:
			current += c
	if not current.is_empty():
		parts.append(current)
	return parts

# Parses "(cols,rows)" → Vector2i(cols, rows). Returns (-1,-1) on failure.
static func _parse_dim(spec: String) -> Vector2i:
	var s := spec.strip_edges().trim_prefix("(").trim_suffix(")")
	var parts := s.split(",")
	if parts.size() == 2:
		var c := parts[0].strip_edges().to_int()
		var r := parts[1].strip_edges().to_int()
		if c > 0 and r > 0:
			return Vector2i(c, r)
	return Vector2i(-1, -1)
