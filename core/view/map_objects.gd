class_name MapObjects
extends RefCounted
## What the scanner shows besides planets and the player's own fleets, from a PlayerView: other
## players' fleets seen this year, minefields known, packets, wormholes and Mystery Traders seen
## (S13, S14, S15, S18).

## seen_fleet keys: owner * FLEET_KEY + fleet number.
const FLEET_KEY := 512
## The other things on the map the player can select, as selection kinds (S13, S14, S12, S18).
const OBJECT_KINDS: Array[String] = ["minefield", "packet", "wormhole", "trader"]


## Other players' fleets the player sees this year (S15 view), in fleet order.
static func seen_fleets(v: PlayerView) -> Array[Fleet]:
	var out: Array[Fleet] = []
	var seen: Dictionary = _view(v).get("fleets", {})
	for f in v.state.fleets:
		if f.owner != v.player and seen.has("%d/%d" % [f.owner, f.number]):
			out.append(f)
	return out


## Key of another player's fleet in a selection ("seen_fleet" kind): owner and fleet number.
static func fleet_key(f: Fleet) -> int:
	return f.owner * FLEET_KEY + f.number


## The other player's fleet with key `key` (fleet_key) if the player sees it this year, else null.
static func seen_fleet(v: PlayerView, key: int) -> Fleet:
	var owner := key / FLEET_KEY
	var f := v.state.fleet(owner, key % FLEET_KEY)
	if f == null or owner == v.player:
		return null
	if not (_view(v).get("fleets", {}) as Dictionary).has("%d/%d" % [owner, f.number]):
		return null
	return f


## What the player sees of another player's fleet (S15): {name, owner, race, x, y, ships, mass},
## each ship row {design, name, count}; {} when the fleet isn't seen.
static func seen_fleet_info(v: PlayerView, key: int) -> Dictionary:
	var f := seen_fleet(v, key)
	if f == null:
		return {}
	var owner := v.state.player(f.owner)
	var ships: Array[Dictionary] = []
	for stack in f.stacks:
		(
			ships
			. append(
				{
					"design": stack.design,
					"name": v.design_name(f.owner, stack.design, false),
					"count": stack.count,
				}
			)
		)
	return {
		"name": v.fleet_name(f),
		"owner": f.owner,
		"race": owner.race.display_name(),
		"x": f.x,
		"y": f.y,
		"ships": ships,
		"mass": FleetTargets.mass_with_cargo(f, owner, v.content),
	}


## Minefields the player owns or knows of (S13, S15).
static func minefields(v: PlayerView) -> Array[Minefield]:
	var out: Array[Minefield] = []
	for m in v.state.minefields:
		if m.owner == v.player or m.known_by.has(v.player):
			out.append(m)
	return out


## Packets and salvage the player sees this year, its own always.
static func packets(v: PlayerView) -> Array[Packet]:
	var out: Array[Packet] = []
	var seen: Array = _view(v).get("packets", [])
	for k in v.state.packets:
		if k.owner == v.player or seen.has("%d/%d" % [k.owner, k.number]):
			out.append(k)
	return out


## Wormholes the player has seen.
static func wormholes(v: PlayerView) -> Array[Wormhole]:
	var out: Array[Wormhole] = []
	var seen: Array = _view(v).get("wormholes", [])
	for w in v.state.wormholes:
		if seen.has(w.number) or w.seen_by.has(v.player):
			out.append(w)
	return out


## Mystery Traders the player sees this year.
static func traders(v: PlayerView) -> Array[Trader]:
	var out: Array[Trader] = []
	var seen: Array = _view(v).get("traders", [])
	for t in v.state.traders:
		if seen.has(t.number):
			out.append(t)
	return out


## The minefields, packets and salvage, wormholes and Mystery Traders the player sees within
## `radius` of a point: [distance, {kind, id}], the id being object_key.
static func objects_near(v: PlayerView, x: float, y: float, radius: float) -> Array:
	var out: Array = []
	for kind in OBJECT_KINDS:
		for o: Variant in _of_kind(v, kind):
			var d := Vector2(o.x - x, o.y - y).length()
			if d <= radius:
				out.append([d, {"kind": kind, "id": object_key(o)}])
	return out


## A map object's key in a selection: owner * FLEET_KEY + number for minefields and packets (which
## each player numbers), the number for wormholes and traders.
static func object_key(o: Variant) -> int:
	if o is Minefield or o is Packet:
		return o.owner * FLEET_KEY + o.number
	return o.number


## The map object of `kind` with key `key` that the player sees, or null.
static func find(v: PlayerView, kind: String, key: int) -> Variant:
	for o: Variant in _of_kind(v, kind):
		if object_key(o) == key:
			return o
	return null


## A map object's name for lists and titles: "Galdric Minefield #3", "Salvage", "Wormhole #2".
static func object_name(v: PlayerView, kind: String, o: Variant) -> String:
	match kind:
		"minefield":
			return "%s Minefield #%d" % [_race(v, o.owner), o.number + 1]
		"packet":
			return "Salvage" if o.salvage else "%s Mineral Packet" % _race(v, o.owner)
		"wormhole":
			return "Wormhole #%d" % (o.number + 1)
		"trader":
			return "Mystery Trader"
	return ""


static func _race(v: PlayerView, owner: int) -> String:
	var p := v.state.player(owner)
	return p.race.display_name() if p != null else "?"


static func _of_kind(v: PlayerView, kind: String) -> Array:
	match kind:
		"minefield":
			return minefields(v)
		"packet":
			return packets(v)
		"wormhole":
			return wormholes(v)
		"trader":
			return traders(v)
	return []


static func _view(v: PlayerView) -> Dictionary:
	if v.player < v.state.views.size() and v.state.views[v.player] is Dictionary:
		return v.state.views[v.player]
	return {}
