class_name Scanning
extends RefCounted
## Scanner ranges, and what the end-of-turn scanning records in the game (spec S15, first part):
## which players know and saw each minefield, and which track each wormhole.
##
## Not yet: cloaking, the fleets and planets each player's view holds, design knowledge,
## Inter-stellar Traveler stargate scanning and Space Demolition minefield scanning.

## Who scans: a fleet, a planet or a Packet Physics packet in flight (S15 "What scanning records").
enum Scanner { FLEET, PLANET, PACKET }

const NO_SCANNER := -1
const PCT := 100
const PMILLE := 1000
## An Alternate Reality planet sees √(POPULATION_RANGE_FACTOR × population in hundreds).
const POPULATION_RANGE_FACTOR := 10
## Penetrating range from a quarter of the normal range: d² ≤ R² div 16.
const NEAR_SHIFT := 4
const BUILTIN_SCANNER_TAG := "builtin_scanner"
const ELECTRONICS := "tech_field.electronics"
## An Alternate Reality planet's starbase of at least this rank gives half its range as
## penetrating range (Ultra Station, Death Star).
const PENETRATING_STARBASE_RANK := 3


## A design's [normal, penetrating] range (`Design_ScannerRange@1030:336a`): the fourth root of
## Σ count × range⁴; normal −1 when the design has no scanner at all.
static func design_ranges(design: Design, owner: Player, content: ContentRegistry) -> Array[int]:
	var normal := 0.0
	var penetrating := 0.0
	var has_scanner := false
	var per_level := RaceMath.trait_param(owner.race, content, "scanner.builtin_per_level", 0)
	var hull_tags: Array = content.hull(design.hull).get("tags", [])
	if per_level > 0 and hull_tags.has(BUILTIN_SCANNER_TAG):
		var level: int = owner.tech_levels[PartRules.tech_order(content)[ELECTRONICS]]
		normal += pow(float(per_level * level), 4)
		penetrating += pow(float(per_level * level / 2), 4)
	for slot in design.parts:
		if slot.count <= 0 or slot.part.is_empty():
			continue
		var part := content.part(slot.part)
		var stats: Dictionary = part.get("stats", {})
		if part.get("category", "") == "scanner":
			has_scanner = true
		normal += slot.count * pow(float(stats.get("scan_range", 0)), 4)
		penetrating += slot.count * pow(float(stats.get("pen_range", 0)), 4)
	var range := NO_SCANNER
	if normal > 0.0 or has_scanner:
		range = int(sqrt(sqrt(normal)))
		range = range * RaceMath.trait_param(owner.race, content, "scanner.range_pct", PCT) / PCT
	return [range, int(sqrt(sqrt(penetrating)))]


## A fleet's [normal, penetrating] range: the largest among the designs it has ships of.
static func fleet_ranges(fleet: Fleet, owner: Player, content: ContentRegistry) -> Array[int]:
	var out: Array[int] = [NO_SCANNER, 0]
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		var r := design_ranges(owner.ship_design(stack.design), owner, content)
		out[0] = maxi(out[0], r[0])
		out[1] = maxi(out[1], r[1])
	return out


## A planet's [normal, penetrating] range (`Planet_ScannerRange@1030:302e`).
static func planet_ranges(state: GameState, content: ContentRegistry, planet: Planet) -> Array[int]:
	var owner := state.player(planet.owner)
	var race := owner.race
	if RaceMath.trait_param(race, content, "scanner.population_range", 0):
		var range := int(sqrt(float(POPULATION_RANGE_FACTOR * planet.population)))
		var nas := RaceMath.trait_param(race, content, "scanner.population_range_pmille", 0)
		if nas > 0:
			return [range * nas / PMILLE, 0]
		var penetrating := 0
		if planet.starbase != null:
			var base := owner.starbase_design(planet.starbase.design)
			if (
				base != null
				and int(content.hull(base.hull).get("rank", 0)) >= PENETRATING_STARBASE_RANK
			):
				penetrating = range / 2
		return [range, penetrating]
	if not planet.has_scanner:
		return [0, 0]
	var best := PartRules.best_part("planetary", "scan_range", owner, content)
	if best.is_empty():
		return [0, 0]
	var stats: Dictionary = content.part(best).get("stats", {})
	var normal: int = (
		int(stats.get("scan_range", 0))
		* RaceMath.trait_param(race, content, "scanner.range_pct", PCT)
		/ PCT
	)
	return [normal, int(stats.get("pen_range", 0))]


## S15 "What scanning records": for each player in order, its fleets, planets and (Packet
## Physics) packets in flight scan minefields and wormholes.
static func record_all(state: GameState, content: ContentRegistry) -> void:
	for p in state.players.size():
		var owner := state.player(p)
		var tracked := {}
		for fleet in state.fleets:
			if fleet.owner != p or fleet.ship_count() == 0:
				continue
			var r := fleet_ranges(fleet, owner, content)
			_scan(state, p, fleet.x, fleet.y, maxi(r[0], 0), r[1], Scanner.FLEET, tracked)
		for planet in state.planets:
			if planet.owner != p:
				continue
			var r := planet_ranges(state, content, planet)
			_scan(state, p, planet.x, planet.y, r[0], r[1], Scanner.PLANET, tracked)
		if RaceMath.trait_param(owner.race, content, "scanner.packets", 0):
			for packet in state.packets:
				if packet.owner == p and not packet.salvage:
					var range := packet.warp * packet.warp
					_scan(state, p, packet.x, packet.y, range, 0, Scanner.PACKET, tracked)


## One scanner of player `p` at (x, y) with normal range `normal` and penetrating range `pen`.
## `tracked` holds the wormholes already tracked by this player's scan.
static func _scan(
	state: GameState,
	p: int,
	x: int,
	y: int,
	normal: int,
	pen: int,
	kind: Scanner,
	tracked: Dictionary
) -> void:
	var r2 := normal * normal
	var near := r2 >> NEAR_SHIFT
	var p2 := pen * pen
	for field in state.minefields:
		if field.seen_by.has(p):
			continue
		var d2 := (field.x - x) * (field.x - x) + (field.y - y) * (field.y - y)
		var known := field.known_by.has(p)
		var seen := false
		match kind:
			Scanner.FLEET:
				seen = d2 <= field.mines or d2 <= p2 or d2 <= near or (known and d2 <= r2)
			Scanner.PLANET:
				seen = d2 <= r2 and (known or d2 <= p2 or d2 <= near)
			Scanner.PACKET:
				seen = d2 <= r2
		if seen:
			_mark(field.known_by, p)
			_mark(field.seen_by, p)
	for w in state.wormholes:
		if tracked.has(w):
			continue
		var d2 := (w.x - x) * (w.x - x) + (w.y - y) * (w.y - y)
		if d2 > r2:
			continue
		if kind == Scanner.PACKET or w.tracked_by.has(p) or d2 <= near or d2 <= p2:
			_mark(w.tracked_by, p)
			tracked[w] = true


static func _mark(players: Array[int], player: int) -> void:
	if not players.has(player):
		players.append(player)
		players.sort()
