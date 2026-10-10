class_name Scanning
extends RefCounted
## Scanner ranges, and what the end-of-turn scanning records (spec S15): which players know and
## saw each minefield, which track each wormhole, and each player's view of the turn: the other
## players' planets, fleets and designs seen and at what detail, the players met, and the packets,
## wormholes and traders in view.
##
## Not yet: full design knowledge from battles and planets seen by bombing fleets (M9), and the
## waypoint changes the original makes when a target is out of sight.

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
const SEES_CARGO_TAG := "steals_from_fleets"
const SEES_MINERALS_TAG := "steals_from_planets"
const ELECTRONICS := "tech_field.electronics"
## An Alternate Reality planet's starbase of at least this rank gives half its range as
## penetrating range (Ultra Station, Death Star).
const PENETRATING_STARBASE_RANK := 3
const REMOTE_MINE := "remote_mine"

## Detail levels (S15 "Detail levels").
const ORBITED := 1
const STARBASE_HIDDEN := 2
const SCANNED := 3
const MINERALS := 4
const FULL := 7


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
	var s := fleet_scanner(fleet, owner, content)
	return [s.range, s.pen]


## A fleet as a scanner (`Fleet_ScannerRanges@1030:31a2`): the largest ranges among its designs,
## the smallest tachyon factor, and whether one of them sees cargo or planet minerals.
static func fleet_scanner(fleet: Fleet, owner: Player, content: ContentRegistry) -> Dictionary:
	var out := {"range": NO_SCANNER, "pen": 0, "tachyon": PCT, "cargo": false, "minerals": false}
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		var design := owner.ship_design(stack.design)
		var r := design_ranges(design, owner, content)
		out.range = maxi(out.range, r[0])
		out.pen = maxi(out.pen, r[1])
		out.tachyon = mini(out.tachyon, Cloaking.tachyon_pct(design, content))
		for slot in design.parts:
			if slot.count > 0 and not slot.part.is_empty():
				var tags: Array = content.part(slot.part).get("tags", [])
				out.cargo = out.cargo or tags.has(SEES_CARGO_TAG)
				out.minerals = out.minerals or tags.has(SEES_MINERALS_TAG)
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


## S15 "What scanning records": for each player in order, its fleets, planets and packets (and a
## Space Demolition player's minefields) scan; `state.views` gets each player's view. `rng` draws
## for Space Demolition minefield scanning.
static func record_all(state: GameState, content: ContentRegistry, rng: StarsRandom = null) -> void:
	state.views.clear()
	for p in state.players.size():
		record_player(state, content, p, rng)
	finish(state)


## One player's pass; players go in order, starting from an empty `state.views`. Returns the
## pass, for the orders that change with what the player sees (Retargeting).
static func record_player(
	state: GameState, content: ContentRegistry, p: int, rng: StarsRandom
) -> Sight:
	var sight := Sight.new(state, content, p, rng)
	sight.run()
	state.views.append(sight.view())
	return sight


## Clears the turn-only marks scanning reads.
static func finish(state: GameState) -> void:
	for fleet in state.fleets:
		fleet.at_bombing = false
	for player in state.players:
		for design in player.ship_designs + player.starbase_designs:
			design.revealed_to.clear()


static func _distance2(x1: int, y1: int, x2: int, y2: int) -> int:
	return (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)


## One player's scanning pass (`ComputeVisibility@1068:5872`).
class Sight:
	var state: GameState
	var content: ContentRegistry
	var p: int
	var me: Player
	var rng: StarsRandom
	## Planet id -> level; fleet -> level (the player's own at FULL).
	var planets := {}
	var fleets := {}
	## [owner, slot] of other players' designs seen this turn.
	var ship_designs := {}
	var starbase_designs := {}
	var met := {}
	var packets := {}
	## Wormholes tracked in this pass.
	var tracked := {}

	func _init(
		p_state: GameState, p_content: ContentRegistry, p_player: int, p_rng: StarsRandom
	) -> void:
		state = p_state
		content = p_content
		p = p_player
		me = state.player(p)
		rng = p_rng

	func run() -> void:
		_start()
		_fleet_scanners()
		_planet_scanners()
		_packet_scanners()
		_minefield_scanners()
		_messages()

	## `Visibility_Reset@1068:58e4`: own planets and fleets, planets orbited by own fleets, packets
	## for a Packet Physics player.
	func _start() -> void:
		for planet in state.planets:
			if planet.owner == p:
				planets[planet.id] = FULL
		for fleet in state.fleets:
			if fleet.owner != p or fleet.ship_count() == 0:
				continue
			fleets[fleet] = FULL
			if fleet.planet < 0:
				continue
			var s := Scanning.fleet_scanner(fleet, me, content)
			var level := ORBITED if s.range < 0 else SCANNED
			if s.minerals or _remote_mining(fleet):
				level = MINERALS
			_see_planet(state.planet(fleet.planet), level)
		if RaceMath.trait_param(me.race, content, "scanner.packets", 0):
			for packet in state.packets:
				_see_packet(packet)

	## A fleet that stayed put and mines an unowned planet sees its minerals.
	func _remote_mining(fleet: Fleet) -> bool:
		if not fleet.did_not_move or state.planet(fleet.planet).owner >= 0:
			return false
		if fleet.waypoints.is_empty() or fleet.waypoints[0].task != REMOTE_MINE:
			return false
		return WaypointTasks.mining_rate(fleet, me, content) > 0

	## `Visibility_FleetScanners@1068:5d44`.
	func _fleet_scanners() -> void:
		for fleet in state.fleets:
			if fleet.ship_count() == 0:
				continue
			if fleet.owner != p:
				# another player's fleet orbiting one of the player's planets
				if _level(fleet) == 0 and fleet.planet >= 0:
					if state.planet(fleet.planet).owner == p:
						_see_fleet(fleet, SCANNED)
				continue
			if fleet.at_bombing:
				_see_planet(state.planet(fleet.planet), SCANNED)
			var s := Scanning.fleet_scanner(fleet, me, content)
			var normal := maxi(s.range, 0)
			for other in state.fleets:
				if other.ship_count() == 0:
					continue
				if s.cargo and other.x == fleet.x and other.y == fleet.y:
					if _level(other) < MINERALS:
						_see_fleet(other, MINERALS)
				_scan_fleet(other, fleet.x, fleet.y, normal, s.pen, s.tachyon, true)
			_scan_objects(fleet.x, fleet.y, normal, s.pen, Scanner.FLEET)
			if s.minerals and fleet.planet >= 0:
				_see_planet(state.planet(fleet.planet), MINERALS)
			if s.pen > 0:
				_scan_planets(fleet.x, fleet.y, s.pen)

	## `Visibility_PlanetScanners@1068:6340`.
	func _planet_scanners() -> void:
		var gate_scanning := RaceMath.trait_param(me.race, content, "scanner.gates", 0) != 0
		for planet in state.planets:
			if planet.owner != p:
				continue
			var r := Scanning.planet_ranges(state, content, planet)
			for other in state.fleets:
				if other.ship_count() > 0:
					_scan_fleet(other, planet.x, planet.y, r[0], r[1], PCT, true)
			_scan_objects(planet.x, planet.y, r[0], r[1], Scanner.PLANET)
			if gate_scanning:
				_scan_gates(planet)
			if r[1] > 0:
				_scan_planets(planet.x, planet.y, r[1])

	## `Visibility_PacketScanners@1068:6bc0`, Packet Physics: packets in flight scan speed² ly.
	func _packet_scanners() -> void:
		if not RaceMath.trait_param(me.race, content, "scanner.packets", 0):
			return
		for packet in state.packets:
			if packet.owner != p or packet.salvage:
				continue
			_see_packet(packet)
			var range := packet.warp * packet.warp
			for other in state.fleets:
				if other.ship_count() > 0:
					_scan_fleet(other, packet.x, packet.y, range, 0, PCT, false)
			_scan_objects(packet.x, packet.y, range, 0, Scanner.PACKET)
			_scan_planets(packet.x, packet.y, range)

	## `Visibility_PacketScanners@1068:6bc0`, Space Demolition: a fleet in deep space inside one
	## of the player's minefields is seen unless its cloak beats random(100).
	func _minefield_scanners() -> void:
		if not RaceMath.trait_param(me.race, content, "scanner.minefields", 0):
			return
		for field in state.minefields:
			if field.owner != p:
				continue
			for other in state.fleets:
				if other.ship_count() == 0 or _level(other) > 0 or other.planet >= 0:
					continue
				if Scanning._distance2(other.x, other.y, field.x, field.y) > field.mines:
					continue
				var cloak := Cloaking.fleet_pct(other, state.player(other.owner), content)
				if cloak == 0 or cloak <= rng.random(PCT):
					_see_fleet(other, SCANNED)

	## `Messages_MarkPlanetsSeen@1028:81b4`: a planet the player lost this turn, named in a message,
	## is seen at level 3.
	func _messages() -> void:
		if p >= state.messages.size():
			return
		for m: Dictionary in state.messages[p]:
			var type: String = m.get("type", "")
			if not content.has_def(type) or not m.get("goto", {}).has("planet"):
				continue
			if content.get_def("message", type).get("reveals_planet", false):
				var planet := state.planet(int(m.goto.planet))
				if planet != null:
					_see_planet(planet, SCANNED)

	## A fleet not seen yet, from a scanner at (x, y): within the normal range and, in orbit,
	## within the penetrating range; cloaking shrinks both (a tachyon factor shrinks the cloak).
	func _scan_fleet(
		other: Fleet, x: int, y: int, normal: int, pen: int, tachyon: int, orbit_rule: bool
	) -> void:
		if _level(other) > 0:
			return
		if absi(other.x - x) > normal or absi(other.y - y) > normal:
			return
		var d2 := Scanning._distance2(other.x, other.y, x, y)
		var orbiting := orbit_rule and other.planet >= 0
		if d2 > normal * normal or (orbiting and d2 > pen * pen):
			return
		var cloak := Cloaking.fleet_pct(other, state.player(other.owner), content)
		if tachyon != PCT:
			cloak = tachyon * cloak / PCT
		if cloak != 0:
			if not Cloaking.within(d2, normal * normal, cloak):
				return
			if orbiting and not Cloaking.within(d2, pen * pen, cloak):
				return
		_see_fleet(other, SCANNED)

	## Planets not seen at level 3 or more within penetrating range `pen` of (x, y).
	func _scan_planets(x: int, y: int, pen: int) -> void:
		var pen2 := pen * pen
		for planet in state.planets:
			if planets.get(planet.id, 0) >= SCANNED:
				continue
			if absi(planet.x - x) > pen or absi(planet.y - y) > pen:
				continue
			var d2 := Scanning._distance2(planet.x, planet.y, x, y)
			if d2 > pen2:
				continue
			var k := Cloaking.starbase_factor(state, content, planet)
			var level := SCANNED
			if k < Cloaking.NO_CLOAK_FACTOR and d2 > k * pen2 / Cloaking.NO_CLOAK_FACTOR:
				level = STARBASE_HIDDEN
			_see_planet(planet, level)

	## Inter-stellar Traveler: a planet's stargate sees the planets with a stargate within its
	## range, cloak permitting.
	func _scan_gates(planet: Planet) -> void:
		var own_gate := Stargates.gate(state, content, planet)
		var range: int = own_gate.get("gate_range", 0)
		if own_gate.is_empty() or range == 0:
			return
		for other in state.planets:
			if planets.get(other.id, 0) >= SCANNED:
				continue
			if Stargates.gate(state, content, other).is_empty():
				continue
			if range > 0:
				if absi(other.x - planet.x) > range or absi(other.y - planet.y) > range:
					continue
				var d2 := Scanning._distance2(other.x, other.y, planet.x, planet.y)
				var k := Cloaking.starbase_factor(state, content, other)
				if d2 > range * range:
					continue
				if (
					k < Cloaking.NO_CLOAK_FACTOR
					and d2 > k * range * range / Cloaking.NO_CLOAK_FACTOR
				):
					continue
			_see_planet(other, SCANNED)

	## Minefields, packets and wormholes from one scanner (S15 first part).
	func _scan_objects(x: int, y: int, normal: int, pen: int, kind: Scanner) -> void:
		var r2 := normal * normal
		var near := r2 >> NEAR_SHIFT
		var p2 := pen * pen
		for field in state.minefields:
			if field.seen_by.has(p):
				continue
			var d2 := Scanning._distance2(field.x, field.y, x, y)
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
				Scanning._mark(field.known_by, p)
				Scanning._mark(field.seen_by, p)
		for packet in state.packets:
			if not packets.has(packet):
				if Scanning._distance2(packet.x, packet.y, x, y) <= r2:
					_see_packet(packet)
		for w in state.wormholes:
			if tracked.has(w):
				continue
			var d2 := Scanning._distance2(w.x, w.y, x, y)
			if d2 > r2:
				continue
			if kind == Scanner.PACKET or w.tracked_by.has(p) or d2 <= near or d2 <= p2:
				Scanning._mark(w.tracked_by, p)
				tracked[w] = true

	func _level(fleet: Fleet) -> int:
		return fleets.get(fleet, 0)

	## `Fleet_MarkSeen@1068:5028`: raises the fleet's level; its designs are seen.
	func _see_fleet(fleet: Fleet, level: int) -> void:
		fleets[fleet] = maxi(_level(fleet), level)
		if fleet.owner == p:
			return
		for stack in fleet.stacks:
			if stack.count != 0:
				ship_designs[[fleet.owner, stack.design]] = true

	## `Planet_MarkSeen@1068:51cc`: raises the planet's level, meets its owner and (unless the
	## starbase stayed hidden) sees its starbase's design.
	func _see_planet(planet: Planet, level: int) -> void:
		planets[planet.id] = maxi(planets.get(planet.id, 0), level)
		if planet.owner < 0 or planet.owner == p:
			return
		met[planet.owner] = true
		if level != STARBASE_HIDDEN and planet.starbase != null:
			starbase_designs[[planet.owner, planet.starbase.design]] = true

	## `Visibility_Designs@1068:71a4`: designs seen this turn get `level`, designs shown in full
	## this turn (a battle, a minefield hit, a caught packet) level 7; their owner is met.
	func _design_levels(
		out: Dictionary, owner: Player, designs: Array, seen: Dictionary, level: int
	) -> void:
		for design: Design in designs:
			var key := [owner.index, design.slot]
			var full := design.revealed_to.has(p)
			if not full and not seen.has(key):
				continue
			out["%d/%d" % key] = FULL if full else level
			met[owner.index] = true

	func _see_packet(packet: Packet) -> void:
		packets[packet] = true
		if packet.owner != p:
			met[packet.owner] = true

	## The player's view (S15 "What scanning records"): other players' things only.
	func view() -> Dictionary:
		for field in state.minefields:
			if field.seen_by.has(p) and field.owner != p:
				met[field.owner] = true
		var design_level := (
			FULL if RaceMath.trait_param(me.race, content, "scanner.full_designs", 0) else SCANNED
		)
		var out := {
			"planets": {},
			"fleets": {},
			"designs": {},
			"starbase_designs": {},
			"met": [],
			"packets": [],
			"wormholes": [],
			"traders": [],
		}
		for planet in state.planets:
			if planet.owner != p and planets.has(planet.id):
				out.planets[str(planet.id)] = planets[planet.id]
		for fleet in state.fleets:
			if fleet.owner != p and fleets.has(fleet):
				out.fleets["%d/%d" % [fleet.owner, fleet.number]] = fleets[fleet]
		for other in state.players:
			if other.index == p:
				continue
			_design_levels(out.designs, other, other.ship_designs, ship_designs, design_level)
			_design_levels(
				out.starbase_designs, other, other.starbase_designs, starbase_designs, design_level
			)
		var others: Array = met.keys()
		others.sort()
		out.met = others
		for packet in state.packets:
			if packets.has(packet):
				out.packets.append("%d/%d" % [packet.owner, packet.number])
		out.packets.sort()
		for w in state.wormholes:
			if tracked.has(w):
				out.wormholes.append(w.number)
		out.wormholes.sort()
		for trader in state.traders:
			out.traders.append(trader.number)
		out.traders.sort()
		return out


static func _mark(players: Array[int], player: int) -> void:
	if not players.has(player):
		players.append(player)
		players.sort()
