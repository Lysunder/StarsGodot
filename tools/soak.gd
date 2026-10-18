extends SceneTree
## Soak test for the computer players (M12 "done when"): AI-only games played to the end, each
## turn checked for orders the host refused, AI step errors and script errors. The first player is
## an inactive human (the idle brain plays it); the others are computer players.
##
## Usage: godot --headless --path . --script res://tools/soak.gd -- [turns] [game ...]
## Games: one per brain (robotoids, turindrones, automitrons, rototills, cybertrons, macinti,
## baseline) and "mixed"; all of them when none is named. Exits 1 when any game had a problem.

const SEED := 4242
const GAMES := {
	"robotoids": [1, ["robotoids"]],
	"turindrones": [1, ["turindrones"]],
	"automitrons": [1, ["automitrons"]],
	"rototills": [1, ["rototills"]],
	"cybertrons": [1, ["cybertrons"]],
	"macinti": [1, ["macinti"]],
	"baseline": [1, ["baseline"]],
	"mixed":
	[
		2,
		[
			"robotoids",
			"turindrones",
			"automitrons",
			"rototills",
			"cybertrons",
			"macinti",
			"baseline"
		]
	],
}
## Computer players per game, at levels Easy .. Expert in turn.
const PLAYERS := 5
## Problems shown per game before the rest are only counted.
const SHOWN := 20

var _log := ErrorLog.new()


## Collects the engine's script errors (a failed turn step otherwise only prints).
class ErrorLog:
	extends Logger
	var errors := PackedStringArray()

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		_error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		errors.append(
			"%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function]
		)

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var turns := int(args[0]) if args.size() > 0 else 200
	var names: Array = args.slice(1) if args.size() > 1 else GAMES.keys()
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	if not r.ok():
		printerr(r.error_text())
		quit(1)
		return
	OS.add_logger(_log)
	var failed := false
	for name: String in names:
		if not GAMES.has(name):
			printerr("unknown game %s" % name)
			failed = true
			continue
		failed = not _soak(r.registry, name, turns) or failed
	quit(1 if failed else 0)


func _soak(content: ContentRegistry, name: String, turns: int) -> bool:
	var spec: Array = GAMES[name]
	var options := NewGame.Options.new()
	options.size = spec[0]
	options.seed = SEED
	var brains: Array = spec[1]
	var count := maxi(PLAYERS, brains.size())
	for i in count:
		var brain: String = brains[i % brains.size()]
		var o := {"ai": brain, "level": i % ComputerPlayers.LEVELS.size(), "personality": {}}
		if brain == AiBrains.BASELINE:
			o["personality"] = PersonalityFile.make("Baseline", AiBrains.BASELINE)
			o["ai"] = NewGame.personality_key(o["personality"])
		options.opponents.append(o)
	var state := NewGame.create(content, options)
	state.player(0).active = false
	var problems := PackedStringArray()
	var started := Time.get_ticks_msec()
	for t in turns:
		var errors := PackedStringArray()
		var sets := ComputerPlayers.add_orders(state, content, [], errors)
		for e in errors:
			problems.append("turn %d AI step: %s" % [state.turn, e])
		var turn := state.turn
		for reason in StandardTurn.generate(state, content, sets):
			problems.append("turn %d host: %s" % [turn, reason])
		for e in _log.errors:
			problems.append("turn %d script error: %s" % [turn, e])
		_log.errors.clear()
		if _alive(state) <= 1:
			break
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	var summary := []
	for p in state.players:
		summary.append(
			(
				"%d:%s %dpl %dfl"
				% [
					p.index,
					p.ai if p.ai != "" else "idle",
					_planets(state, p.index),
					_fleets(state, p.index)
				]
			)
		)
	print(
		(
			"%s: turn %d in %.0fs, %d problems; %s"
			% [name, state.turn, seconds, problems.size(), ", ".join(PackedStringArray(summary))]
		)
	)
	for i in mini(problems.size(), SHOWN):
		print("  " + problems[i])
	return problems.is_empty()


func _alive(state: GameState) -> int:
	var n := 0
	for p in state.players:
		if not p.eliminated and not p.is_human():
			n += 1
	return n


func _planets(state: GameState, player: int) -> int:
	var n := 0
	for pl in state.planets:
		if pl.owner == player:
			n += 1
	return n


func _fleets(state: GameState, player: int) -> int:
	var n := 0
	for f in state.fleets:
		if f.owner == player:
			n += 1
	return n
