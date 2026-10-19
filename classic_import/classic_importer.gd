class_name ClassicImporter
extends RefCounted
## The classic look (spec S26; decision D13): reads the player's own copy of Stars! 2.6i and writes
## a cosmetic mod, `user://mods/classic/`, that shows the original's pictures through the art ids
## our game uses. Nothing it reads or writes is ever part of the repository or shipped: it runs on
## the player's machine, from the player's files.
##
## Output (S26 "Output layout"): `art/sheets/<resource id>.png`, each sprite sheet converted whole;
## `art/index.json`, art id -> {file, rect}; and `mod.json`, written last, so a half-finished import
## is never loaded; with `text`, `lang/en.json` too: the original's turn-message wording for each
## message our content maps to an original number (legacy_ids.json), where its codes fit our
## parameters (ClassicText; owner's decision, 2026-10-18). The sheets' layouts, the part picture
## numbers and the message table's place come from `content/core/classic_ids.json` (numbers only);
## ship pictures from each hull's `pictures`.

const EXE := "stars26i.exe"
const MOD_ID := "classic"
const OUT_DIR := "user://mods/" + MOD_ID
const IDS_PATH := "res://content/core/classic_ids.json"
const VERSION := "1.0.0"
const LEGACY_PATH := "res://content/core/legacy_ids.json"


class Result:
	extends RefCounted
	var errors := PackedStringArray()
	var lines := PackedStringArray()
	## How many art ids the index holds; message texts imported and kept as ours.
	var art := 0
	var texts := 0
	var kept := 0

	func ok() -> bool:
		return errors.is_empty()


## Imports from the install folder `install_dir` into `out_dir` (normally OUT_DIR), with the hulls
## and parts of `content`.
static func run(
	install_dir: String, content: ContentRegistry, out_dir := OUT_DIR, text := true
) -> Result:
	var r := Result.new()
	var exe_path := _find_file(install_dir, EXE)
	if exe_path.is_empty():
		r.errors.append("%s was not found in %s." % [EXE, install_dir])
		return r
	var exe := NeResources.read(FileAccess.get_file_as_bytes(exe_path))
	if not exe.ok():
		r.errors.append("%s: %s." % [EXE, exe.error])
		return r
	var ids: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(IDS_PATH))
	var sheets := _sheet_ids(ids)
	var missing := PackedInt32Array()
	for id in sheets:
		if exe.get_resource(NeResources.BITMAP, id).is_empty():
			missing.append(id)
	if not missing.is_empty():
		r.errors.append(
			"This copy is missing pictures %s: is it Stars! 2.6i?" % ", ".join(Array(missing))
		)
		return r
	# start clean: no manifest until everything is written
	_remove_tree(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("art/sheets"))
	for id in sheets:
		var image := NeResources.bitmap_image(exe.get_resource(NeResources.BITMAP, id))
		if image == null:
			r.errors.append("Picture %d could not be read." % id)
			return r
		image.save_png(out_dir.path_join("art/sheets/%d.png" % id))
	var index := _index(ids, content)
	r.art = index.size()
	var f := FileAccess.open(out_dir.path_join("art/index.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(index, " ", true))
	f.close()
	if text:
		_import_text(exe, ids["messages"], content, out_dir, r)
	var manifest := {
		"id": MOD_ID,
		"name": "Classic Look",
		"version": VERSION,
		"api_version": ModLoader.API_VERSION,
		"kind": "cosmetic",
		"description":
		"Pictures from your own copy of Stars! 2.6i, made on this computer. Never share this folder.",
	}
	f = FileAccess.open(out_dir.path_join("mod.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	r.lines.append("Imported %d pictures from %d sheets." % [r.art, sheets.size()])
	if text:
		r.lines.append("Imported the wording of %d messages (%d keep ours)." % [r.texts, r.kept])
	return r


## `lang/en.json`: the original's wording of every message our content maps to an original number,
## where its codes fit our parameters.
static func _import_text(
	exe: NeResources, table: Dictionary, content: ContentRegistry, out_dir: String, r: Result
) -> void:
	var seg := exe.segment(int(table["segment"]))
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_PATH))
	var strings := {}
	var ids: Array = legacy.keys()
	ids.sort()
	for id: String in ids:
		var entry: Variant = legacy[id]
		if not entry is Dictionary or not entry.has("message") or not content.has_def(id):
			continue
		var template := ClassicText.get_text(seg, table, int(entry["message"]))
		var params: Array = content.get_def("message", id).get("params", [])
		var converted := ClassicText.convert_template(template, params, table["codes"])
		if converted.is_empty():
			r.kept += 1
			continue
		strings[id + ".text"] = converted
		r.texts += 1
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("lang"))
	var f := FileAccess.open(out_dir.path_join("lang/en.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(strings, " ", true))
	f.close()


## Every sheet resource id the index uses.
static func _sheet_ids(ids: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	for id: Variant in (
		ids["ships"]["sheets"] + ids["ships"]["small_sheets"] + ids["parts"]["sheets"]
	):
		out.append(int(id))
	out.append(int(ids["planets"]["sheet"]))
	for key: String in ids["race_logos"]["sheets"]:
		out.append(int(ids["race_logos"]["sheets"][key]))
	out.append(int(ids["objects"]["sheet"]))
	out.append(int(ids["title"]))
	return out


## Art id -> {file, rect} (S26 section 1).
static func _index(ids: Dictionary, content: ContentRegistry) -> Dictionary:
	var out := {}
	var ships: Dictionary = ids["ships"]
	for hull_id in content.ids("hull"):
		var hull := content.hull(hull_id)
		if not hull.has("pictures"):
			continue
		for k in 4:
			var n: int = (int(hull["pictures"]) + k) % int(ships["count"])
			var column := (n / 4) % int(ships["columns"])
			var row := n % int(ships["rows"])
			var sheet := n / int(ships["per_sheet"])
			var t := int(ships["tile"])
			var s := int(ships["small_tile"])
			out["art.%s.%d" % [hull_id, k]] = _tile(ships["sheets"][sheet], column * t, row * t, t)
			out["art.%s.%d.small" % [hull_id, k]] = _tile(
				ships["small_sheets"][sheet], column * s, row * s, s
			)
	var parts: Dictionary = ids["parts"]
	var pt := int(parts["tile"])
	for part_id: String in ids["part_pictures"]:
		var p := int(ids["part_pictures"][part_id])
		var sheet: Variant = parts["sheets"][p / int(parts["per_sheet"])]
		var column := p % int(parts["columns"])
		var row := (p / int(parts["columns"])) % int(parts["rows"])
		out["art." + part_id] = _tile(sheet, column * pt, row * pt, pt)
	var planets: Dictionary = ids["planets"]
	var lt := int(planets["tile"])
	for k in int(planets["count"]):
		var column := k % int(planets["columns"])
		var row := int(planets["rows"]) - 1 - k / int(planets["columns"])
		out["art.planet.%d" % k] = _tile(planets["sheet"], column * lt, row * lt, lt)
	var logos: Dictionary = ids["race_logos"]
	for suffix: String in logos["sheets"]:
		var t := int(logos["tiles"][suffix])
		for logo in int(logos["count"]):
			var x := (logo % int(logos["columns"])) * t
			var y := (logo / int(logos["columns"])) * t
			out["art.race_logo.%d%s" % [logo, suffix]] = _tile(logos["sheets"][suffix], x, y, t)
	var objects: Dictionary = ids["objects"]
	var ot := int(objects["tile"])
	for i in (objects["ids"] as Array).size():
		out["art.object." + str(objects["ids"][i])] = _tile(objects["sheet"], i * ot, 0, ot)
	out["art.title"] = {"file": "sheets/%d.png" % int(ids["title"])}
	return out


static func _tile(sheet: Variant, x: int, y: int, size: int) -> Dictionary:
	return {"file": "sheets/%d.png" % int(sheet), "rect": [x, y, size, size]}


## The file named `name` in `dir`, matched without regard to case ("" when absent).
static func _find_file(dir: String, name: String) -> String:
	for f in DirAccess.get_files_at(dir):
		if f.to_lower() == name.to_lower():
			return dir.path_join(f)
	return ""


static func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
