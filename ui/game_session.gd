extends Node
## The running game for the UI (autoload `GameSession`): content, the current state, the
## player's pending orders and their preview (OrderPreview), and new game / load / save /
## end turn. Scenes read `view` and call these methods; they never change the state themselves.

signal changed

const SAVE_DIR := "user://saves"
const PLAYER := 0

var content: ContentRegistry
var load_errors: String = ""
var state: GameState = null
var orders: OrderSet = null
var preview: OrderPreview = null
var view: PlayerView = null
var game_version: String = "0.1.0"


func _ready() -> void:
	var loader := ModLoader.new()
	game_version = loader.game_version
	var r := loader.load_mods(FolderModSource.discover("res://content"), [])
	if r.ok():
		content = r.registry
	else:
		load_errors = r.error_text()
		push_error(load_errors)


func has_game() -> bool:
	return state != null


func new_game(options: NewGame.Options) -> void:
	_start(NewGame.create(content, options))


## Loads a save (and its pending orders, if saved with them); returns "" or the problems.
func load_game(path: String) -> String:
	var result := SaveStore.read(path, content)
	if not result.ok():
		return "\n".join(result.errors)
	_start(result.state)
	var orders_path := path + ".orders"
	if FileAccess.file_exists(orders_path):
		var o := OrderFile.read(orders_path)
		if o.ok() and o.order_set.turn == state.turn:
			orders = o.order_set
			_refresh()
	return ""


func save_game(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := SaveStore.write(path, state, game_version)
	if err == OK:
		err = OrderFile.write(path + ".orders", orders, game_version)
	return err


func default_save_path() -> String:
	return "%s/game.json" % SAVE_DIR


## Adds an order; returns "" or why it was rejected (a rejected order is not kept).
func add_order(order: Dictionary) -> String:
	orders.add(order)
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


## Generates the turn with the pending orders; returns the rejected orders' reasons.
func end_turn() -> PackedStringArray:
	var sets: Array[OrderSet] = [orders]
	var rejected := StandardTurn.generate(state, content, sets)
	orders = OrderSet.new(PLAYER, state.turn)
	_refresh()
	return rejected


func _start(s: GameState) -> void:
	state = s
	orders = OrderSet.new(PLAYER, state.turn)
	_refresh()


func _refresh() -> void:
	preview = OrderPreview.build(state, content, orders)
	view = PlayerView.new(preview.state, content, PLAYER)
	changed.emit()


func _rejection_of(index: int) -> String:
	var prefix := "player %d order %d: " % [PLAYER, index]
	for line in preview.rejected:
		if line.begins_with(prefix):
			return line.substr(prefix.length())
	return ""


static func _key(order: Dictionary) -> String:
	match order.get("type"):
		"production_queue", "planet_settings":
			return "%s/%s" % [order["type"], order.get("planet")]
		"research", "player_defaults":
			return order["type"]
		"fleet_repeat", "fleet_rename", "fleet_battle_plan":
			return "%s/%s" % [order["type"], order.get("fleet")]
	return ""
