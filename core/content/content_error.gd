class_name ContentError
extends RefCounted
## One problem found while loading mods or content: which mod, which file, which line, and what.

var mod_id: String
var file: String
var line: int
var message: String


func _init(p_mod_id: String, p_file: String, p_line: int, p_message: String) -> void:
	mod_id = p_mod_id
	file = p_file
	line = p_line
	message = p_message


func _to_string() -> String:
	var where := mod_id
	if not file.is_empty():
		where += ":" + file
		if line > 0:
			where += ":%d" % line
	return "%s: %s" % [where, message]
