extends SceneTree
## The play-by-email host tool (spec S27 "Play by email"), headless:
##
##   godot --headless --path <project> --script res://tools/host.gd -- new <dir> <setup.json>
##   godot --headless --path <project> --script res://tools/host.gd -- status <dir>
##   godot --headless --path <project> --script res://tools/host.gd -- generate <dir> [--force]
##   ... -- inactive <dir> <N>
##   ... -- active <dir> <N>
##   ... -- hand-over <dir> <N> <ai> [level]
##
## `new` makes a game in <dir> from a setup file and writes the human players' turn files; send
## each player theirs (<name>-p<N>.turn). Players open it in the game, give their orders and send
## back <name>-p<N>.orders; put those in <dir>. `status` shows who has sent theirs; `generate`
## turns the year when all are in (`--force`: without the missing ones) and writes new turn files.
## `inactive` stops waiting for player N (the computer keeps their things ticking over) until
## `active`; `hand-over` gives player N to a computer personality for good (level as below).
##
## Setup file (JSON): {"name": "mygame", "seed": 1234, "size": "small", "density": "normal",
## "positions": "moderate", "flags": ["slow_tech", ...], "players": [...]}, where each player is
## {"race_file": "<path to a race file>"} or {"preset": "warrior"} for a human (the first player
## must be human), or {"ai": "robotoids", "level": "expert"} for a computer player (level "random"
## or left out: drawn).

const LEVELS := ["easy", "standard", "harder", "expert"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var loader := ModLoader.new()
	var r := loader.load_mods(FolderModSource.discover("res://content"), [])
	if not r.ok():
		printerr(r.error_text())
		quit(2)
		return
	var content: ContentRegistry = r.registry
	var result: PbemHost.Result = null
	var command: String = args[0] if args.size() > 0 else ""
	match command:
		"new":
			if args.size() < 3:
				result = _usage()
			else:
				result = _new(args[1], args[2], content, loader.game_version)
		"status":
			result = PbemHost.status(args[1], content) if args.size() > 1 else _usage()
		"generate":
			if args.size() < 2:
				result = _usage()
			else:
				result = PbemHost.generate(
					args[1], content, loader.game_version, args.has("--force")
				)
		"inactive", "active":
			if args.size() < 3:
				result = _usage()
			else:
				var active := command == "active"
				result = PbemHost.set_active(
					args[1], int(args[2]) - 1, active, content, loader.game_version
				)
		"hand-over":
			if args.size() < 4:
				result = _usage()
			else:
				var level := LEVELS.find(args[4]) if args.size() > 4 else 1
				result = PbemHost.hand_over(
					args[1], int(args[2]) - 1, args[3], maxi(level, 0), content, loader.game_version
				)
		_:
			result = _usage()
	for line in result.lines:
		print(line)
	for e in result.errors:
		printerr(e)
	quit(0 if result.ok() else 1)


func _usage() -> PbemHost.Result:
	var r := PbemHost.Result.new()
	r.errors.append(
		(
			"usage: new <dir> <setup.json> | status <dir> | generate <dir> [--force]"
			+ " | inactive <dir> <N> | active <dir> <N> | hand-over <dir> <N> <ai> [level]"
		)
	)
	return r


func _new(
	dir: String, setup_path: String, content: ContentRegistry, version: String
) -> PbemHost.Result:
	var r := PbemHost.Result.new()
	var setup: Variant = JSON.parse_string(FileAccess.get_file_as_string(setup_path))
	if not setup is Dictionary:
		r.errors.append("cannot read the setup file %s" % setup_path)
		return r
	var options := NewGame.Options.new()
	var size: Variant = setup.get("size", "small")
	options.size = NewGame.SIZES.find(size) if size is String else int(size)
	options.density = str(setup.get("density", "normal"))
	options.positions = str(setup.get("positions", "moderate"))
	options.seed = int(setup.get("seed", 1))
	for flag: Variant in setup.get("flags", []):
		options.flags.append(str(flag))
	var players: Array = setup.get("players", [])
	if options.size < 0 or players.is_empty():
		r.errors.append("the setup needs a size from %s and at least one player" % [NewGame.SIZES])
		return r
	for i in players.size():
		var entry: Dictionary = players[i]
		if entry.has("ai"):
			if i == 0:
				r.errors.append("the first player must be human")
				return r
			var level := LEVELS.find(str(entry.get("level", "random")))
			options.opponents.append({"ai": str(entry["ai"]), "level": level, "personality": {}})
			continue
		var race := _race(entry, setup_path.get_base_dir(), content, r)
		if race == null:
			return r
		if i == 0:
			options.race = race
		else:
			options.opponents.append({"human": true, "race": race})
	return PbemHost.create(dir, str(setup.get("name", "")), options, content, version)


func _race(entry: Dictionary, base: String, content: ContentRegistry, r: PbemHost.Result) -> Race:
	if entry.has("race_file"):
		var path := str(entry["race_file"])
		if path.is_relative_path():
			path = base.path_join(path)
		var loaded := RaceFile.read(path, content)
		if not loaded.ok():
			r.errors.append("%s: %s" % [path, "; ".join(loaded.errors)])
			return null
		return loaded.race
	var preset := "race_preset." + str(entry.get("preset", "default"))
	if not RacePresets.ids(content).has(preset):
		r.errors.append("no race preset %s" % preset)
		return null
	return RacePresets.make(content, preset)
