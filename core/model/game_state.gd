class_name GameState
extends ModelObject
## The whole state of one game (spec S03): everything a turn reads and writes.
##
## Collections are lists in the S03 order and are kept that way: players by index, planets by id,
## fleets and space objects by (owner, number). Create fleets and space objects with the add_*
## functions, which apply the original's "lowest free number" rule. The original's combined order
## of all space objects is minefields, then packets and salvage, then wormholes, then traders.

## Year shown to players for turn 0.
const FIRST_YEAR := 2400

var turn: int = 0
var settings: GameSettings = GameSettings.new()
var players: Array[Player] = []
var planets: Array[Planet] = []
var fleets: Array[Fleet] = []
var minefields: Array[Minefield] = []
var packets: Array[Packet] = []
var wormholes: Array[Wormhole] = []
var traders: Array[Trader] = []
## The random streams (S01). Saved under "rng".
var rng: RngStreams = RngStreams.new(0)
## Per player, this turn's messages (S21).
var messages: Array = []
## This turn's battle records (S16).
var battles: Array = []
## Per player, score history (S20).
var history: Array = []
var mod_data: Dictionary = {}


func _schema() -> Array:
	return [
		["turn", Kind.INT],
		["settings", Kind.OBJECT, GameSettings],
		["players", Kind.OBJECT_LIST, Player],
		["planets", Kind.OBJECT_LIST, Planet],
		["fleets", Kind.OBJECT_LIST, Fleet],
		["minefields", Kind.OBJECT_LIST, Minefield],
		["packets", Kind.OBJECT_LIST, Packet],
		["wormholes", Kind.OBJECT_LIST, Wormhole],
		["traders", Kind.OBJECT_LIST, Trader],
		["messages", Kind.JSON],
		["battles", Kind.JSON],
		["history", Kind.JSON],
		["mod_data", Kind.JSON],
	]


func year() -> int:
	return FIRST_YEAR + turn


func to_dict() -> Dictionary:
	var out := super.to_dict()
	out["rng"] = rng.to_dict()
	return out


func load_dict(data: Variant, path: String, errors: PackedStringArray) -> void:
	if not data is Dictionary:
		errors.append("%s: expected an object" % path)
		return
	var rest: Dictionary = data.duplicate()
	if not rest.has("rng"):
		errors.append("%s/rng: missing" % path)
	else:
		var streams := RngStreams.from_dict(rest["rng"] if rest["rng"] is Dictionary else {})
		if streams == null:
			errors.append("%s/rng: invalid random stream state" % path)
		else:
			rng = streams
		rest.erase("rng")
	super.load_dict(rest, path, errors)
	if errors.is_empty():
		_check_order(path, errors)


# --- Lookups ---------------------------------------------------------------------------------


func player(index: int) -> Player:
	return players[index] if index >= 0 and index < players.size() else null


func planet(id: int) -> Planet:
	return planets[id] if id >= 0 and id < planets.size() else null


func fleet(owner: int, number: int) -> Fleet:
	var at := _search(fleets, owner, number)
	return fleets[at] if at < fleets.size() and _key_of(fleets[at]) == [owner, number] else null


## Fleets of one player, in number order.
func fleets_of(owner: int) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for f in fleets:
		if f.owner == owner:
			out.append(f)
	return out


## Every space object in the original's combined order (minefields, packets and salvage,
## wormholes, traders; each by owner then number).
func space_objects() -> Array[ModelObject]:
	var out: Array[ModelObject] = []
	out.append_array(minefields)
	out.append_array(packets)
	out.append_array(wormholes)
	out.append_array(traders)
	return out


# --- Creation and removal --------------------------------------------------------------------


## Creates a fleet of the owner with the lowest free number, inserted in order. Returns null when
## the owner already has `limit` fleets.
func add_fleet(owner: int, limit: int) -> Fleet:
	var created := Fleet.new()
	created.owner = owner
	return _insert_numbered(fleets, created, limit) as Fleet


func remove_fleet(f: Fleet) -> void:
	fleets.erase(f)


func add_minefield(owner: int, limit: int) -> Minefield:
	var created := Minefield.new()
	created.owner = owner
	return _insert_numbered(minefields, created, limit) as Minefield


## A packet, or salvage when `salvage` is true (they share one numbering).
func add_packet(owner: int, salvage: bool, limit: int) -> Packet:
	var created := Packet.new()
	created.owner = owner
	created.salvage = salvage
	return _insert_numbered(packets, created, limit) as Packet


func add_wormhole(limit: int) -> Wormhole:
	return _insert_numbered(wormholes, Wormhole.new(), limit) as Wormhole


func add_trader(limit: int) -> Trader:
	return _insert_numbered(traders, Trader.new(), limit) as Trader


func space_object_count() -> int:
	return minefields.size() + packets.size() + wormholes.size() + traders.size()


# --- Ordering helpers ------------------------------------------------------------------------


## (owner, number) of a numbered object; objects without an owner use -1.
static func _key_of(obj: ModelObject) -> Array:
	var owner: Variant = obj.get("owner")
	return [-1 if owner == null else int(owner), int(obj.get("number"))]


static func _key_less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])


## First position whose key is not below (owner, number).
static func _search(list: Array, owner: int, number: int) -> int:
	var lo := 0
	var hi := list.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if _key_less(_key_of(list[mid]), [owner, number]):
			lo = mid + 1
		else:
			hi = mid
	return lo


## Gives obj the lowest number its owner doesn't use, and inserts it in order.
static func _insert_numbered(list: Array, obj: ModelObject, limit: int) -> ModelObject:
	var owner: int = _key_of(obj)[0]
	var at := _search(list, owner, 0)
	var number := 0
	while at < list.size() and _key_of(list[at]) == [owner, number]:
		number += 1
		at += 1
	if number >= limit:
		return null
	obj.set("number", number)
	list.insert(at, obj)
	return obj


func _check_order(path: String, errors: PackedStringArray) -> void:
	for i in players.size():
		if players[i].index != i:
			errors.append("%s/players/%d/index: must be %d" % [path, i, i])
	for i in planets.size():
		if planets[i].id != i:
			errors.append("%s/planets/%d/id: must be %d" % [path, i, i])
	for list_name in ["fleets", "minefields", "packets", "wormholes", "traders"]:
		var list: Array = get(list_name)
		for i in range(1, list.size()):
			if not _key_less(_key_of(list[i - 1]), _key_of(list[i])):
				errors.append(
					"%s/%s/%d: not in (owner, number) order or a duplicate" % [path, list_name, i]
				)
	for f in fleets:
		for i in range(1, f.stacks.size()):
			if f.stacks[i - 1].design >= f.stacks[i].design:
				errors.append(
					"%s/fleets: fleet %d/%d stacks not in design order" % [path, f.owner, f.number]
				)
	for p in players:
		for list_name in ["ship_designs", "starbase_designs"]:
			var designs: Array = p.get(list_name)
			for i in range(1, designs.size()):
				if designs[i - 1].slot >= designs[i].slot:
					errors.append(
						"%s/players/%d/%s: not in slot order" % [path, p.index, list_name]
					)
