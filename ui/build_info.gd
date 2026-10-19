class_name BuildInfo
extends RefCounted
## Which build this is, for the window title and the About box: the game version and, in a build
## made by tools/build.sh, the commit and date it was made from (res://build_info.json, written by
## that script and never committed). A game run from the editor says "dev".

const PATH := "res://build_info.json"


## "0.1.0 (abc1234, 2026-10-19)" in a build, "0.1.0 (dev)" otherwise.
static func label() -> String:
	var version := ModLoader.new().game_version
	if not FileAccess.file_exists(PATH):
		return TranslationServer.translate("%s (dev)") % version
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		return TranslationServer.translate("%s (dev)") % version
	return "%s (%s, %s)" % [version, data.get("commit", "?"), data.get("date", "?")]
