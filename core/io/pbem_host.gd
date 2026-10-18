class_name PbemHost
extends RefCounted
## The play-by-email host (spec S27 "Play by email"): a game kept in a folder, turned by the host
## player when every human player's orders are in.
##
## The folder holds `host.json` ({format, format_version, game_id, name}), the game (`game.json`,
## a save, SaveFile), each human player's turn file (`<name>-p<N>.turn`, TurnFile, N counting from
## 1) and the orders they send back (`<name>-p<N>.orders`, OrderSubmission). Generating a year
## takes every human's orders (computer players adding theirs, S22), writes the new turn files and
## moves the orders used to `done/<year index>/`.

const FORMAT := "starsgodot-host"
const FORMAT_VERSION := 1
const HOST_FILE := "host.json"
const GAME_FILE := "game.json"
const DONE_DIR := "done"
const GAME_ID_LENGTH := 16


class Result:
	extends RefCounted
	var errors := PackedStringArray()
	## What happened, a line each (for the host tool to print).
	var lines := PackedStringArray()
	## Human players (indices) whose orders are in for the year, and those still awaited.
	var submitted: Array[int] = []
	var waiting: Array[int] = []
	## Whether a year was generated.
	var generated := false

	func ok() -> bool:
		return errors.is_empty()


## Makes a new game in `dir` (which must not hold one yet) and writes the human players' first
## turn files.
static func create(
	dir: String,
	game_name: String,
	options: NewGame.Options,
	content: ContentRegistry,
	game_version: String
) -> Result:
	var r := Result.new()
	if FileAccess.file_exists(dir.path_join(HOST_FILE)):
		r.errors.append("%s already holds a game" % dir)
		return r
	if game_name.is_empty() or game_name != game_name.validate_filename():
		r.errors.append("the game name must be usable as a file name")
		return r
	DirAccess.make_dir_recursive_absolute(dir)
	var state := NewGame.create(content, options)
	var text := SaveFile.encode(state, game_version)
	var host := {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"game_id": text.sha256_text().left(GAME_ID_LENGTH),
		"name": game_name,
	}
	var err := SaveStore.write_text(dir.path_join(HOST_FILE), JSON.stringify(host, "  ") + "\n")
	if err == OK:
		err = SaveStore.write_text(dir.path_join(GAME_FILE), text)
	if err != OK:
		r.errors.append("cannot write to %s (%s)" % [dir, error_string(err)])
		return r
	_write_turn_files(dir, host, state, game_version, r)
	r.lines.append("New game %s (id %s) in %s." % [game_name, host["game_id"], dir])
	return r


## Who has sent their orders for the year and who is awaited.
static func status(dir: String, content: ContentRegistry) -> Result:
	var r := Result.new()
	var host := _read_host(dir, r)
	var state := _read_game(dir, content, r)
	if not r.ok():
		return r
	_collect(dir, host, state, r)
	r.lines.insert(0, "%s: year %d (turn %d)." % [host["name"], state.year(), state.turn])
	for p in _givers(state):
		var who := "player %d (%s)" % [p + 1, state.player(p).race.display_plural()]
		r.lines.append("%s: %s" % [who, "submitted" if r.submitted.has(p) else "waiting"])
	return r


## Generates the year when every human player's orders are in (with `force`, those missing give
## none), then writes the new turn files.
static func generate(
	dir: String, content: ContentRegistry, game_version: String, force := false
) -> Result:
	var r := Result.new()
	var host := _read_host(dir, r)
	var state := _read_game(dir, content, r)
	if not r.ok():
		return r
	var sets := _collect(dir, host, state, r)
	if not r.waiting.is_empty() and not force:
		var names := PackedStringArray()
		for p in r.waiting:
			names.append(str(p + 1))
		r.lines.append("Waiting for player(s) %s; nothing generated." % ", ".join(names))
		return r
	var given: Array[OrderSet] = []
	for p in _givers(state):
		given.append(sets.get(p, OrderSet.new(p, state.turn)))
	var problems := PackedStringArray()
	var all := ComputerPlayers.add_orders(state, content, given, problems)
	for problem in problems:
		r.lines.append("AI: " + problem)
	var turn := state.turn
	for line in StandardTurn.generate(state, content, all):
		r.lines.append("Refused: " + line)
	var err := SaveStore.write(dir.path_join(GAME_FILE), state, game_version)
	if err != OK:
		r.errors.append("cannot save the game (%s)" % error_string(err))
		return r
	var done := dir.path_join(DONE_DIR).path_join(str(turn))
	DirAccess.make_dir_recursive_absolute(done)
	for p in sets:
		var file := _orders_name(host, p)
		DirAccess.rename_absolute(dir.path_join(file), done.path_join(file))
	_write_turn_files(dir, host, state, game_version, r)
	r.generated = true
	r.lines.append("Generated year %d." % state.year())
	return r


## Marks human player `p` (an index) inactive or active again. An inactive human gives no orders;
## the inactive personality keeps their things ticking over (S22) until they come back.
static func set_active(
	dir: String, p: int, active: bool, content: ContentRegistry, game_version: String
) -> Result:
	var r := Result.new()
	var host := _read_host(dir, r)
	var state := _read_game(dir, content, r)
	if not r.ok():
		return r
	if p < 0 or p >= state.players.size() or not state.player(p).is_human():
		r.errors.append("player %d is not a human player" % (p + 1))
		return r
	state.player(p).active = active
	_save(dir, host, state, game_version, r)
	r.lines.append(
		(
			"Player %d is %s."
			% [p + 1, "active again" if active else "inactive (the computer keeps house)"]
		)
	)
	return r


## Hands human player `p` to a computer player for good: personality key `ai` at `level` (an index
## into ComputerPlayers.LEVELS), keeping the race (S22).
static func hand_over(
	dir: String, p: int, ai: String, level: int, content: ContentRegistry, game_version: String
) -> Result:
	var r := Result.new()
	var host := _read_host(dir, r)
	var state := _read_game(dir, content, r)
	if not r.ok():
		return r
	if p < 0 or p >= state.players.size() or not state.player(p).is_human():
		r.errors.append("player %d is not a human player" % (p + 1))
		return r
	if not ComputerPlayers.RACES.has(ai):
		r.errors.append("no computer personality %s (one of %s)" % [ai, ComputerPlayers.RACES])
		return r
	var player := state.player(p)
	player.ai = ai
	player.ai_level = clampi(level, 0, ComputerPlayers.LEVELS.size() - 1)
	player.active = true
	ComputerPlayers.adopt_personalities(state, content)
	_save(dir, host, state, game_version, r)
	r.lines.append(
		(
			"Player %d is now played by the computer (%s, %s)."
			% [p + 1, ai, ComputerPlayers.LEVELS[player.ai_level]]
		)
	)
	return r


## Saves the game after a change made between years, with fresh turn files, and puts away orders
## a player handed over no longer needs.
static func _save(
	dir: String, host: Dictionary, state: GameState, game_version: String, r: Result
) -> void:
	var err := SaveStore.write(dir.path_join(GAME_FILE), state, game_version)
	if err != OK:
		r.errors.append("cannot save the game (%s)" % error_string(err))
		return
	for p in state.players:
		var path := dir.path_join(_orders_name(host, p.index))
		if not p.is_human() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_write_turn_files(dir, host, state, game_version, r)


## The human players who give orders: active and not eliminated (S27).
static func _givers(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for p in state.players:
		if p.is_human() and p.active and not p.eliminated:
			out.append(p.index)
	return out


static func turn_file_name(host: Dictionary, p: int) -> String:
	return "%s-p%d.%s" % [host["name"], p + 1, TurnFile.EXTENSION]


static func _orders_name(host: Dictionary, p: int) -> String:
	return "%s-p%d.%s" % [host["name"], p + 1, OrderSubmission.EXTENSION]


## Every human player's turn file (the eliminated ones too, to see the game go on).
static func _write_turn_files(
	dir: String, host: Dictionary, state: GameState, game_version: String, r: Result
) -> void:
	for p in state.players:
		if not p.is_human():
			continue
		var path := dir.path_join(turn_file_name(host, p.index))
		var err := TurnFile.write(path, state, p.index, host["game_id"], game_version)
		if err != OK:
			r.errors.append("cannot write %s (%s)" % [path, error_string(err)])


## The orders sent for this year, by player; fills `submitted` and `waiting`, and notes files
## that are refused (damaged, or for another game, player or year).
static func _collect(dir: String, host: Dictionary, state: GameState, r: Result) -> Dictionary:
	var sets := {}
	for p in _givers(state):
		var path := dir.path_join(_orders_name(host, p))
		if not FileAccess.file_exists(path):
			r.waiting.append(p)
			continue
		var o := OrderSubmission.read(path)
		var problem := ""
		if not o.ok():
			problem = "; ".join(o.errors)
		elif o.game_id != host["game_id"]:
			problem = "orders for another game"
		elif o.order_set.player != p:
			problem = "orders of player %d" % (o.order_set.player + 1)
		elif o.order_set.turn != state.turn:
			problem = "orders for turn %d, not %d" % [o.order_set.turn, state.turn]
		if not problem.is_empty():
			r.lines.append("Refused %s: %s." % [path.get_file(), problem])
			r.waiting.append(p)
			continue
		sets[p] = o.order_set
		r.submitted.append(p)
	return sets


static func _read_host(dir: String, r: Result) -> Dictionary:
	var text := FileAccess.get_file_as_string(dir.path_join(HOST_FILE))
	var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not data is Dictionary or data.get("format") != FORMAT:
		r.errors.append("%s holds no play-by-email game" % dir)
		return {}
	return data


## The game, refused when made with other gameplay content (S03: a host never plays a save the
## players' games would disagree with).
static func _read_game(dir: String, content: ContentRegistry, r: Result) -> GameState:
	if not r.ok():
		return null
	var loaded := SaveStore.read(dir.path_join(GAME_FILE), content)
	if not loaded.ok():
		r.errors.append_array(loaded.errors)
		return null
	if loaded.needs_confirmation():
		r.errors.append("the game was made with other gameplay content or mods")
		return null
	return loaded.state
