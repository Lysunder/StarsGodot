class_name SaveStore
extends RefCounted
## Reads and writes save files (format in SaveFile). Writes go to a temporary file first and then
## replace the target, so a crash while saving never leaves a half-written save.

const TEMP_SUFFIX := ".tmp"


static func write(path: String, state: GameState, game_version: String) -> Error:
	return write_text(path, SaveFile.encode(state, game_version))


## Writes text to a temporary file, then replaces `path` with it.
static func write_text(path: String, text: String) -> Error:
	var temp := path + TEMP_SUFFIX
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	var err := file.get_error()
	file.close()
	if err != OK:
		DirAccess.remove_absolute(temp)
		return err
	# rename replaces an existing file in one step on every platform Godot supports
	return DirAccess.rename_absolute(temp, path)


static func read(path: String, content: ContentRegistry) -> SaveFile.LoadResult:
	if not FileAccess.file_exists(path):
		var missing := SaveFile.LoadResult.new()
		missing.errors.append("%s: no such file" % path)
		return missing
	var result := SaveFile.decode(FileAccess.get_file_as_string(path), content)
	var prefixed := PackedStringArray()
	for e in result.errors:
		prefixed.append("%s: %s" % [path, e])
	result.errors = prefixed
	return result
