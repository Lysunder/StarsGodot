extends Node
## The running game for the UI (autoload `GameSession`): content, the current state, the
## player's pending orders and their preview (OrderPreview), and new game / load / save /
## end turn. Scenes read `view` and call these methods; they never change the state themselves.
##
## Hotseat (S27): with several human players, `player` is the one at the controls. Ending a turn
## submits that player's orders and hands over to the next human who has not submitted; after the
## last one the year is generated (computer players adding theirs) and the first human is up.
##
## Play by email (S27): a turn file opened from the host holds the game as one player knows it;
## ending the turn (or saving) writes that player's orders beside it, to send back to the host.

signal changed
## Another human player is at the controls (hotseat), before the screen shows their game.
signal player_changed

const SAVE_DIR := "user://saves"
## The save's companion files: each human's pending orders, and the hotseat round.
const ORDERS_SUFFIX := ".orders"
const PLAYER_ORDERS_SUFFIX := ".p%d.orders"
const ROUND_SUFFIX := ".round"

var content: ContentRegistry
var load_errors: String = ""
var state: GameState = null
var orders: OrderSet = null
var preview: OrderPreview = null
var view: PlayerView = null
var game_version: String = "0.1.0"
## The human player at the controls.
var player: int = 0
## The orders refused when the last year was generated, one "player P order I: reason" line each.
var rejected := PackedStringArray()
## The play-by-email turn file being played ("" otherwise) and its game's id.
var turn_file := ""
var game_id := ""
## Orders changed since the game was last saved or loaded (the Messages pane's "*").
var dirty: bool = false
## This year's orders of the human players by index (the one at the controls included), and the
## players who have ended their turn.
var _orders := {}
var _submitted := {}


func _ready() -> void:
	game_version = ModLoader.new().game_version
	reload_content()


## Loads the content with the player's mods (ModSettings: those turned on, in order, script mods
## only when trusted). When they don't load, the base game loads alone and `load_errors` says why.
func reload_content() -> void:
	ArtRegistry.reload()
	load_errors = ""
	var r := load_mods(ModSettings.enabled())
	if not r.ok():
		load_errors = (
			"The mods could not be loaded, so the game runs without them:\n" + r.error_text()
		)
		push_warning(load_errors)
		r = load_mods(PackedStringArray())
	if r.ok():
		content = r.registry
	else:
		load_errors = r.error_text()
		push_error(load_errors)


## The content with `enabled` mods (and the base game), trusted as the player trusts them.
func load_mods(enabled: PackedStringArray) -> ModLoader.LoadResult:
	var loader := ModLoader.new()
	loader.trusted = ModSettings.trusted()
	return loader.load_mods(ModSettings.sources(), enabled)


func has_game() -> bool:
	return state != null


func new_game(options: NewGame.Options) -> void:
	_start(NewGame.create(content, options))


## Opens a play-by-email turn file (and the orders already written for it, to go on with them);
## returns "" or the problems.
func open_turn_file(path: String) -> String:
	var loaded := TurnFile.read(path, content)
	if not loaded.ok():
		return "\n".join(loaded.errors)
	if loaded.content_mismatch:
		return "The turn file was made with other gameplay content or mods than this game has."
	_start(loaded.state)
	turn_file = path
	game_id = loaded.game_id
	player = loaded.player
	var sent := OrderSubmission.read(submission_path())
	if (
		sent.ok()
		and sent.game_id == game_id
		and sent.order_set.player == player
		and sent.order_set.turn == state.turn
	):
		_orders[player] = sent.order_set
	orders = _orders_of(player)
	_refresh()
	return ""


func is_pbem() -> bool:
	return not turn_file.is_empty()


## Where the orders for the turn file go: beside it, `.orders` for `.turn`.
func submission_path() -> String:
	return turn_file.get_basename() + "." + OrderSubmission.EXTENSION


## Writes the player's orders for the turn file; returns "" or why it failed.
func submit_orders() -> String:
	var err := OrderSubmission.write(submission_path(), orders, game_id, game_version)
	if err != OK:
		return "The orders could not be written (%s)." % error_string(err)
	dirty = false
	changed.emit()
	return ""


## Loads a save (and the human players' pending orders and the hotseat round, if saved with
## them); returns "" or the problems.
func load_game(path: String) -> String:
	var result := SaveStore.read(path, content)
	if result.ok() and result.content_mismatch:
		var switched := _content_for(result.saved_mods)
		if switched.is_empty():
			result = SaveStore.read(path, content)
		else:
			return switched
	if not result.ok():
		return "\n".join(result.errors)
	_start(result.state)
	for p in humans():
		var orders_path := _orders_path(path, p)
		if not FileAccess.file_exists(orders_path):
			continue
		var o := OrderFile.read(orders_path)
		if o.ok() and o.order_set.turn == state.turn and o.order_set.player == p:
			_orders[p] = o.order_set
	var round_text := FileAccess.get_file_as_string(path + ROUND_SUFFIX)
	var round: Variant = JSON.parse_string(round_text) if not round_text.is_empty() else null
	if round is Dictionary and int(round.get("turn", -1)) == state.turn:
		for p: Variant in round.get("submitted", []):
			if humans().has(int(p)):
				_submitted[int(p)] = true
		if humans().has(int(round.get("player", -1))):
			player = int(round["player"])
	orders = _orders_of(player)
	_refresh()
	return ""


func save_game(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := SaveStore.write(path, state, game_version)
	_orders[player] = orders
	for p in humans():
		if err == OK:
			err = OrderFile.write(_orders_path(path, p), _orders_of(p), game_version)
	if err == OK:
		var round := {"turn": state.turn, "player": player, "submitted": _submitted.keys()}
		err = SaveStore.write_text(path + ROUND_SUFFIX, JSON.stringify(round))
	if err == OK:
		dirty = false
		changed.emit()
	return err


## Switches the content to the gameplay mods a saved game was played with (keeping the player's
## cosmetic mods), when they are all installed and load; returns "" or why the game can't load.
func _content_for(saved: PackedStringArray) -> String:
	var installed := {}
	for source in ModSettings.sources():
		var m := ModManifest.from_json(source.read_text(ModManifest.FILE), source.root())
		if m.errors.is_empty():
			installed[m.id] = m
	var wanted := PackedStringArray()
	var missing := PackedStringArray()
	for entry in saved:
		var at := entry.rfind("@")
		var id := entry.substr(0, at)
		var version := entry.substr(at + 1)
		if id == ModLoader.CORE_ID:
			continue
		if not installed.has(id) or (installed[id] as ModManifest).version != version:
			missing.append("%s %s" % [id, version])
		else:
			wanted.append(id)
	if not missing.is_empty():
		return "This game needs mods that are not installed: %s." % ", ".join(missing)
	for id in ModSettings.enabled():
		if installed.has(id) and (installed[id] as ModManifest).kind == "cosmetic":
			wanted.append(id)
	var r := load_mods(wanted)
	if not r.ok():
		return "This game's mods could not be loaded:\n" + r.error_text()
	if r.registry.gameplay_mods() != saved:
		return "This game was played with other mods or content: %s." % ", ".join(saved)
	content = r.registry
	return ""


## The human players who give orders this year, in player order: active and not eliminated.
func humans() -> Array[int]:
	var out: Array[int] = []
	if state == null:
		return out
	for p in state.players:
		if p.is_human() and p.active and not p.eliminated:
			out.append(p.index)
	return out


## Whether the game has more than one human player giving orders at this screen (hotseat; a
## play-by-email turn file is one player's).
func is_hotseat() -> bool:
	return not is_pbem() and humans().size() > 1


func _orders_of(p: int) -> OrderSet:
	if not _orders.has(p):
		_orders[p] = OrderSet.new(p, state.turn)
	return _orders[p]


static func _orders_path(path: String, p: int) -> String:
	return path + (ORDERS_SUFFIX if p == 0 else PLAYER_ORDERS_SUFFIX % p)


func default_save_path() -> String:
	return "%s/game.json" % SAVE_DIR


## Adds an order; returns "" or why it was rejected (a rejected order is not kept).
func add_order(order: Dictionary) -> String:
	orders.add(order)
	dirty = true
	_refresh()
	var reason := _rejection_of(orders.orders.size() - 1)
	if not reason.is_empty():
		orders.orders.pop_back()
		_refresh()
	return reason


## Adds an order, or replaces the last pending order when it is the same kind of edit of the same
## waypoint (so a warp or amount being adjusted step by step stays one order).
func amend_order(order: Dictionary) -> String:
	if orders.orders.is_empty():
		return add_order(order)
	var last: Dictionary = orders.orders[-1]
	for field: String in ["type", "owner", "fleet", "index"]:
		if last.get(field) != order.get(field):
			return add_order(order)
	orders.orders.pop_back()
	var reason := add_order(order)
	if not reason.is_empty():
		orders.orders.append(last)
		_refresh()
	return reason


## Replaces the pending order of the same kind for the same thing (a planet's queue, the research
## settings, the player defaults), or adds it.
func set_order(order: Dictionary) -> String:
	var key := _key(order)
	if key.is_empty():
		return add_order(order)
	for i in range(orders.orders.size() - 1, -1, -1):
		if _key(orders.orders[i]) == key:
			orders.orders.remove_at(i)
	return add_order(order)


## Ends the turn of the player at the controls. While another human player has not ended theirs,
## hands over to the next one (S27) and returns false; otherwise generates the year with every
## human's orders and the computer players' (S22), puts the first human at the controls and returns
## true (the refused orders in `rejected`). An eliminated player at the controls, alone, still
## generates years to watch.
func end_turn() -> bool:
	_orders[player] = orders
	_submitted[player] = true
	for p in humans():
		if not _submitted.has(p):
			_switch_to(p)
			return false
	var given: Array[OrderSet] = []
	for p: int in _orders:
		if _submitted.has(p):
			given.append(_orders[p])
	var problems := PackedStringArray()
	var sets := ComputerPlayers.add_orders(state, content, given, problems)
	for problem in problems:
		push_warning(problem)
	rejected = StandardTurn.generate(state, content, sets)
	_orders.clear()
	_submitted.clear()
	dirty = true
	var first := humans()
	if first.is_empty() or first[0] == player:
		orders = _orders_of(player)
		_refresh()
	else:
		_switch_to(first[0])
	return true


## The refused orders of the last year that were the player at the controls'.
func my_rejections() -> PackedStringArray:
	var out := PackedStringArray()
	var prefix := "player %d " % player
	for line in rejected:
		if line.begins_with(prefix):
			out.append(line)
	return out


func _switch_to(p: int) -> void:
	player = p
	orders = _orders_of(p)
	_refresh()
	player_changed.emit()


func _start(s: GameState) -> void:
	state = s
	dirty = false
	turn_file = ""
	game_id = ""
	_orders.clear()
	_submitted.clear()
	rejected = PackedStringArray()
	var first := humans()
	player = first[0] if not first.is_empty() else 0
	orders = _orders_of(player)
	_refresh()


func _refresh() -> void:
	preview = OrderPreview.build(state, content, orders)
	view = PlayerView.new(preview.state, content, player)
	changed.emit()


func _rejection_of(index: int) -> String:
	var prefix := "player %d order %d: " % [player, index]
	for line in preview.rejected:
		if line.begins_with(prefix):
			return line.substr(prefix.length())
	return ""


static func _key(order: Dictionary) -> String:
	match order.get("type"):
		"production_queue", "planet_settings":
			return "%s/%s" % [order["type"], order.get("planet")]
		"research", "player_defaults", "message_filters", "player_relations":
			return order["type"]
		"fleet_repeat", "fleet_rename", "fleet_battle_plan":
			return "%s/%s" % [order["type"], order.get("fleet")]
		"minefield_detonate":
			return "%s/%s" % [order["type"], order.get("minefield")]
	return ""
