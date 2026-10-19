class_name MapObjects
extends RefCounted
## What the scanner shows besides planets and the player's own fleets, from a PlayerView: other
## players' fleets seen this year, minefields known, packets, wormholes and Mystery Traders seen
## (S13, S14, S15, S18).


## Other players' fleets the player sees this year (S15 view), in fleet order.
static func seen_fleets(v: PlayerView) -> Array[Fleet]:
	var out: Array[Fleet] = []
	var seen: Dictionary = _view(v).get("fleets", {})
	for f in v.state.fleets:
		if f.owner != v.player and seen.has("%d/%d" % [f.owner, f.number]):
			out.append(f)
	return out


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


static func _view(v: PlayerView) -> Dictionary:
	if v.player < v.state.views.size() and v.state.views[v.player] is Dictionary:
		return v.state.views[v.player]
	return {}
