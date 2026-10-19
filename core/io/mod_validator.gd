class_name ModValidator
extends RefCounted
## The mod validator's checks (plan M14; MODDING.md §13; the command line is
## tools/validate_mod.gd): a mod folder's manifest; the game's core loaded with the mod (and the
## mods it needs), as the game would, so every content, patch, string and script problem comes with
## its file and line; the mod's scripts against the determinism rules (MODDING.md §8); and a list
## of what the mod adds or changes. Validating a script mod runs its entry script.

## Patterns a mod script must not use: [regex, what it is].
const RULES := [
	["\\b(randi|randf|randi_range|randf_range|randfn|randomize|seed)\\s*\\(", "engine randomness"],
	["\\bRandomNumberGenerator\\b", "engine randomness"],
	["\\b(Time|OS|Engine|Performance)\\s*\\.", "clocks, OS or engine state"],
	["\\b(FileAccess|DirAccess|HTTPRequest)\\b", "files or network"],
	["\\bstatic\\s+var\\b", "static (global) state"],
	["\\bget_tree\\s*\\(", "the SceneTree"],
]


class Result:
	extends RefCounted
	## The mod's id ("" when its manifest can't be read).
	var mod_id := ""
	var problems := PackedStringArray()
	## What the mod is and changes, a line each.
	var lines := PackedStringArray()

	func ok() -> bool:
		return problems.is_empty()


## Checks the mod in `folder`, with the mods in `with` (folders) it needs enabled too.
static func validate(folder: String, with: Array[String] = []) -> Result:
	var r := Result.new()
	var source := FolderModSource.new(folder.trim_suffix("/"))
	if not source.has_file(ModManifest.FILE):
		r.problems.append("%s: no %s" % [folder, ModManifest.FILE])
		return r
	var manifest := ModManifest.from_json(source.read_text(ModManifest.FILE), folder)
	for e in manifest.errors:
		r.problems.append(str(e))
	if not manifest.errors.is_empty():
		return r
	r.mod_id = manifest.id
	r.lines.append(
		"%s %s (%s mod), %s" % [manifest.name, manifest.version, manifest.kind, manifest.id]
	)
	for path in source.list_files("", "gd"):
		_lint(source, path, r)
	var sources: Array[ModSource] = FolderModSource.discover("res://content")
	var enabled := PackedStringArray()
	var loader := ModLoader.new()
	for other_folder in with:
		var other := FolderModSource.new(other_folder.trim_suffix("/"))
		var m := ModManifest.from_json(other.read_text(ModManifest.FILE), other_folder)
		sources.append(other)
		enabled.append(m.id)
		loader.trusted[m.id] = ModLoader.script_hash(other)
	sources.append(source)
	enabled.append(manifest.id)
	loader.trusted[manifest.id] = ModLoader.script_hash(source)
	var loaded := loader.load_mods(sources, enabled)
	for e in loaded.errors:
		r.problems.append(str(e))
	if loaded.ok():
		_summary(manifest, source, loaded.registry, r)
	return r


## The determinism rules, line by line (comments left out).
static func _lint(source: ModSource, path: String, r: Result) -> void:
	var lines := source.read_text(path).split("\n")
	for i in lines.size():
		var code := lines[i]
		var hash := code.find("#")
		if hash >= 0:
			code = code.substr(0, hash)
		for rule: Array in RULES:
			if RegEx.create_from_string(rule[0]).search(code) != null:
				r.problems.append("%s:%d: uses %s (MODDING.md §8)" % [path, i + 1, rule[1]])


static func _summary(
	manifest: ModManifest, source: ModSource, content: ContentRegistry, r: Result
) -> void:
	var added := {}
	var patched := PackedStringArray()
	for type_name: String in ContentSchemas.TYPES:
		for id in content.ids(type_name):
			for entry in content.provenance(id):
				if not entry.begins_with(manifest.id + ":"):
					continue
				if entry.contains(":patch"):
					patched.append(id)
				else:
					added[type_name] = added.get(type_name, 0) + 1
	for type_name: String in added:
		r.lines.append("adds or replaces %d %s definition(s)" % [added[type_name], type_name])
	if not patched.is_empty():
		r.lines.append("patches %s" % ", ".join(patched))
	var langs := source.list_files("lang", "json")
	if not langs.is_empty():
		r.lines.append("strings in %s" % ", ".join(langs))
	var standard := StandardRuleset.build()
	for id in content.ruleset.ids():
		if not standard.has(id):
			r.lines.append("adds formula %s" % id)
		elif content.ruleset.formula(id) != standard.formula(id):
			r.lines.append("replaces formula %s" % id)
	for edit: Array in content.phase_edits:
		if edit[3] == manifest.id:
			var phase := (edit[2] as Phase).id if edit[2] != null else ""
			r.lines.append("turn phases: %s %s %s" % [edit[0], edit[1], phase])
