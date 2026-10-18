class_name ClassicPlanning
extends RefCounted
## The production every classic personality plans each turn (spec S22 "Classic production"):
## the pass over its planets after the fleets have their orders (`AI_ManageProduction`), with
## starbases, ships, packets, defenses and terraforming, the late-game defenses, the mines put
## ahead of a waiting item (`AI_FixupMineOrders`), and the last pass that fills each queue with
## factories and mines (`AI_FinishTurn`, `AI_FillPlanetQueue`).

const P := preload("res://core/ai/classic/classic_production.gd")

## Population (hundreds) a Robotoids planet needs before it plans production; other personalities
## plan below OTHERS_MIN_POPULATION only where planet_info byte INFO_DEPOT_PLAN is clear.
const ROBOTOIDS_MIN_POPULATION := 40
const OTHERS_MIN_POPULATION := 60
const INFO_DEPOT_PLAN := 2
const INFO_BOMBERS := 8
## Starbases: the population a depot planet needs, and the turn before which every personality
## queues them.
const STARBASE_MIN_POPULATION := 80
const STARBASE_EARLY_TURN := 31
const CYBERTRONS_SHIP_TURN := 40
## Starbase upgrades: per hundred chance 5 plus half the design's age over 10 turns (whole age
## from 50), and the minerals each kind a growing starbase needs on the surface.
const UPGRADE_MIN_MINERALS := 200
## Defenses: population (hundreds) before a planet builds them, one per DEFENSE_POPULATION of it,
## at most MAX_DEFENSE_ITEMS a time.
const DEFENSE_MIN_POPULATION := 1600
const DEFENSE_POPULATION := 80
const MAX_ITEMS_AT_ONCE := 4
const TERRAFORM_MIN_POPULATION := 200
## Packets (`AI_QueuePackets`): the level needed, minerals in hand, the driver warp, and the reach
## squared with one or two of the best drivers (three times that with a mineral over
## PACKET_RICH_SURFACE).
const PACKET_MIN_LEVEL := 2
const PACKET_MIN_MINERALS := 3001
const PACKET_MIN_WARP := 10
const PACKET_REACH2 := [7056, 50625]
const PACKET_RICH_SURFACE := 12500
const PACKET_WARP := 13
const PACKET_FRESH_TURNS := 2
const PACKET_STRONG_DEFENSE := 14
const PACKET_BIG_POPULATION := 750
## Late-game defenses start at turn (universe size index + LATE_DEFENSE_OFFSET) * 10.
const LATE_DEFENSE_OFFSET := 2
const DEFENSE_MIN_RESOURCES := 50
const DEFENSE_EXTRA_RESOURCES := 150
const DEFENSE_ALCHEMY_PER_EXTRA := 5
## Mines ahead of a waiting item: years standing in for "never".
const NEVER_FIRST := 600
const NEVER_LATER := 700
## Alchemy fills the queue only once every field is at this level, after ALCHEMY_TURN.
const ALCHEMY_TECH := 26
const ALCHEMY_TURN := 100
const MACINTI_TERRAFORM_RESOURCES := 70


static func _info(w: ClassicWorld, planet_id: int, byte: int) -> int:
	return (w.planet_info[planet_id] as PackedByteArray)[byte]


# --- The production pass -----------------------------------------------------------------------


## `AI_ManageProduction`: fleets' safe speeds, depot starbases, then each of the player's planets
## (shuffled order) that has the people and, unless Macinti, the minerals for its queue
## (the queue's cost within this year's output for each mineral): a starbase upgrade, else
## packets, else defenses (other personalities: only where INFO_DEPOT_PLAN is clear, Cybertrons a
## starbase upgrade only), else (not Robotoids) terraforming. Then the late-game defenses and the
## mines ahead of waiting items.
static func manage(w: ClassicWorld, station: int) -> void:
	ClassicFleets.avoid_minefields(w)
	queue_starbases(w, station)
	var pid := w.personality_id()
	for planet in w.own_planets:
		if pid == ClassicWorld.ROBOTOIDS:
			if planet.population < ROBOTOIDS_MIN_POPULATION:
				continue
		elif planet.population < OTHERS_MIN_POPULATION and _info(w, planet.id, 2) == 0:
			continue
		var out := P.output(w, planet)
		var cost := P.queue_cost(w, planet)
		if pid != ClassicWorld.MACINTI:
			var i := 0
			while i < 4 and cost[i] <= out[i]:
				i += 1
			if i < 3:
				continue
		w.select_planet(planet.id)
		P.open(w)
		var changed := false
		if pid == ClassicWorld.ROBOTOIDS or _info(w, planet.id, INFO_DEPOT_PLAN) == 0:
			changed = (
				queue_ship(w, planet, station)
				or queue_packets(w, planet, out)
				or queue_defenses(w, planet)
			)
		elif pid == ClassicWorld.CYBERTRONS:
			changed = queue_ship(w, planet, station)
		if pid != ClassicWorld.ROBOTOIDS and not changed:
			changed = queue_terraform(w, planet)
		P.commit(w, changed)
	var size := w.state.settings.universe_width / 400 - 1
	if not w.state.settings.tutorial and (size + LATE_DEFENSE_OFFSET) * 10 <= w.state.turn:
		late_game_defenses(w)
	fixup_mines(w)


## A starbase item in the edited queue.
static func _starbase_queued(w: ClassicWorld) -> bool:
	for q in (w.editing as P.Edit).queue:
		if q.is_design() and q.starbase:
			return true
	return false


## `AI_QueueStarbase`: each of the player's planets without a starbase that is a freighter depot,
## has STARBASE_MIN_POPULATION people and INFO_DEPOT_PLAN clear queues `station` unless a starbase
## is queued there; Cybertrons instead every planet `choose_starbase` picks. Not Macinti; in a
## tutorial game only before STARBASE_EARLY_TURN.
static func queue_starbases(w: ClassicWorld, station: int) -> void:
	var pid := w.personality_id()
	if pid == ClassicWorld.MACINTI:
		return
	if w.state.settings.tutorial and w.state.turn >= STARBASE_EARLY_TURN:
		return
	for planet in w.state.planets:
		if planet.owner != w.player:
			continue
		var slot := -1
		if pid == ClassicWorld.CYBERTRONS:
			slot = choose_starbase(w, planet)
		elif (
			planet.starbase == null
			and planet.population >= STARBASE_MIN_POPULATION
			and _info(w, planet.id, INFO_DEPOT_PLAN) == 0
			and w.is_depot(planet.id)
		):
			slot = station
		if slot < 0:
			continue
		w.select_planet(planet.id)
		P.open(w)
		if _starbase_queued(w):
			P.commit(w, false)
		else:
			P.add(w, P.starbase(slot), 1, P.Mode.APPEND)
			P.commit(w, true)


## `AI_ChooseStarbasePlanet` (Cybertrons): a planet without a starbase, at least 15% habitable,
## with 500 people, gets the newer station (all concentrations 16 or more) or the newer fort;
## -1 for others. The planet is selected and its production opened.
static func choose_starbase(w: ClassicWorld, planet: Planet) -> int:
	if planet.starbase != null:
		return -1
	if PlanetEconomy.hab_value(planet, w.me().race) < 15 or planet.population < 500:
		return -1
	w.select_planet(planet.id)
	P.open(w)
	if planet.concentration.all(func(c: int) -> bool: return c >= 16):
		return ClassicDesigns.newer_starbase(w, 0, 5)
	return ClassicDesigns.newer_starbase(w, 1, 6)


## `AI_QueueShip`: the planet's starbase grows. A starbase of an older generation than the newest
## station (`station`) or fort is replaced by the same size of the newest, with a chance per
## hundred of 5 plus half the newest design's age past 10 turns (the whole age from 50). One of
## the newest generation grows to the next size with a chance of 6 in 100 when that design exists
## and the surface has UPGRADE_MIN_MINERALS of each mineral. Not when a starbase is queued, not
## Cybertrons before CYBERTRONS_SHIP_TURN; Macinti's own way comes with Macinti.
static func queue_ship(w: ClassicWorld, planet: Planet, station: int) -> bool:
	if planet.starbase != null and _starbase_queued(w):
		return false
	var pid := w.personality_id()
	if pid == ClassicWorld.MACINTI:
		return _queue_macinti_starbase(w, planet)
	if pid == ClassicWorld.CYBERTRONS and w.state.turn < CYBERTRONS_SHIP_TURN:
		return false
	if planet.starbase == null:
		return false
	var current := planet.starbase.design
	var fort := ClassicDesigns.FORT_SLOTS.has(current)
	var newest := station
	var sizes := 3
	if fort:
		sizes = 2
		newest = ClassicDesigns.newer_starbase(w, 1, 6)
	var item: int
	if current < newest or current > (sizes - 1) * 2 + newest:
		var d := w.me().starbase_design(newest)
		var age := w.state.turn - (0 if d == null else d.turn_designed) - 10
		if age < 0:
			age = 0
		elif age < 50:
			age = age >> 1
		if w.rng.random(100) >= age + 5:
			return false
		item = current % 5 + newest - (1 if fort else 0)
	else:
		if current % 5 >= (sizes - 1) * 2:
			return false
		if w.me().starbase_design(current + 2) == null:
			return false
		if w.rng.random(100) > 5:
			return false
		for m in 3:
			if planet.surface[m] < UPGRADE_MIN_MINERALS:
				return false
		item = current + 2
	P.add(w, P.starbase(item), 1, P.Mode.APPEND)
	return true


## Macinti's starbase step (`AI_QueueShip`): by the verdict of the planet's starbase slot (0 with
## none): replaced (3, or 2 on a draw of 10 in 100) by the next slot whose verdict is 0 (slots 0-3,
## at most 9), or across generations (slots 4-9, three on, else three back); otherwise slots 0-3
## grow the same way on a draw of (crowding - 15) x 6 in 100 from crowding 16 on, and slots 4, 5,
## 7, 8 grow to the next slot on a draw of 8 in 100.
static func _queue_macinti_starbase(w: ClassicWorld, planet: Planet) -> bool:
	var v: PackedByteArray = w.macinti_verdicts
	if v.size() < 10:
		return false
	var s := planet.starbase.design if planet.starbase != null else 0
	var t := -1
	if v[s] == 3 or (v[s] == 2 and w.rng.random(100) < 10):
		t = _macinti_next(v, s)
	elif s < 4 or s == 6 or s == 9 or w.rng.random(100) > 7:
		if s > 3:
			return false
		var most := PlanetEconomy.max_pop(planet, w.me().race, w.content)
		var crowding := 0
		if most > 0:
			crowding = mini((most / 2 + planet.population * 100) / most, 999)
		if crowding < 16:
			return false
		if w.rng.random(100) >= (crowding - 15) * 6:
			return false
		t = _macinti_next(v, s)
	else:
		t = s + 1
	P.add(w, P.starbase(t), 1, P.Mode.APPEND)
	return true


static func _macinti_next(v: PackedByteArray, s: int) -> int:
	if s < 4:
		var t := s + 1
		while t < 9 and v[t] != 0:
			t += 1
		return t
	return s + 3 if s + 3 <= 9 else s - 3


## `AI_QueuePackets`: from level PACKET_MIN_LEVEL, with PACKET_MIN_MINERALS of output and a
## driver of PACKET_MIN_WARP or more, one turn in four (a draw) the planet aims its driver at
## warp PACKET_WARP at another player's planet seen in the last PACKET_FRESH_TURNS turns within
## reach that is weakly defended or lightly peopled (`packet.no_damage` races left out, and
## starbases of `ai.no_packets_at_starbases` races), one drawn among them, and queues packets: 80
## of germanium now and then (output over 20000 and a draw), mixed ones when rich in all three,
## else each mineral over what it keeps. Not Cybertrons, and not when packets are queued.
static func queue_packets(w: ClassicWorld, planet: Planet, out: Array[int]) -> bool:
	if w.personality_id() == ClassicWorld.CYBERTRONS:
		return false
	for q in (w.editing as P.Edit).queue:
		if not q.is_design() and P.PACKETS.has(q.item):
			return false
	if w.me().ai_level < PACKET_MIN_LEVEL:
		return false
	if out[0] + out[1] + out[2] < PACKET_MIN_MINERALS:
		return false
	if planet.starbase == null:
		return false
	var driver := Packets.driver(w.state, w.content, planet)
	if driver[0] < PACKET_MIN_WARP:
		return false
	if w.rng.random(4) != 0:
		return false
	var reach2: int = PACKET_REACH2[driver[1]]
	for m in 3:
		if planet.surface[m] > PACKET_RICH_SURFACE:
			reach2 *= 3
			break
	var count := 0
	var target: Planet = null
	for p in w.state.planets:
		if p.owner == -1 or p.owner == w.player:
			continue
		if int(w.seen_turn.get(p.id, 0)) + PACKET_FRESH_TURNS < w.state.turn:
			continue
		if (
			p.defense_estimate >= PACKET_STRONG_DEFENSE
			and p.population_estimate >= PACKET_BIG_POPULATION
		):
			continue
		var race := w.state.player(p.owner).race
		if RaceMath.trait_param(race, w.content, "packet.no_damage", 0):
			continue
		if (
			p.starbase != null
			and RaceMath.trait_param(race, w.content, "ai.no_packets_at_starbases", 0)
		):
			continue
		var dx := planet.x - p.x
		var dy := planet.y - p.y
		if dx * dx + dy * dy <= reach2:
			count += 1
			if w.rng.random(count) == 0:
				target = p
	if target == null:
		return false
	var cur := w.cur_planet
	cur.mass_driver_target = target.id
	cur.mass_driver_warp = PACKET_WARP
	(
		w
		. order(
			{
				"type": "planet_settings",
				"planet": cur.id,
				"leftover_to_research": cur.leftover_to_research,
				"mass_driver_target": target.id,
				"mass_driver_warp": PACKET_WARP,
				"route": cur.route,
			}
		)
	)
	if out[2] > 20000 and w.rng.random(3) != 0:
		P.add(w, P.standard(P.PACKETS[2]), 80, P.Mode.APPEND)
	if out[0] > 3000 and out[1] > 4000 and out[2] > 3000:
		P.add(w, P.standard(P.PACKETS[3]), 30, P.Mode.APPEND)
	elif out[0] > 1500 and out[1] > 2250 and out[2] > 1500:
		P.add(w, P.standard(P.PACKETS[3]), 15, P.Mode.APPEND)
	else:
		for m in 3:
			var keep := 2500 if m == 1 else 1250
			if out[m] > keep:
				P.add(
					w, P.standard(P.PACKETS[m]), clampi((out[m] - keep) / 200, 1, 25), P.Mode.APPEND
				)
	return true


## The list item of `item`'s kind when it offers some, else null.
static func _offered(w: ClassicWorld, item: String) -> QueueItem:
	var b := (w.editing as P.Edit).listed(P.standard(item))
	return b if b != null and b.count != 0 else null


## `AI_QueueDefenses`: a planet of DEFENSE_MIN_POPULATION with fewer defenses than one per
## DEFENSE_POPULATION queues up to MAX_ITEMS_AT_ONCE, unless defenses are queued.
static func queue_defenses(w: ClassicWorld, planet: Planet) -> bool:
	if planet.population < DEFENSE_MIN_POPULATION:
		return false
	if planet.defenses >= planet.population / DEFENSE_POPULATION:
		return false
	if (w.editing as P.Edit).queued(P.standard(P.DEFENSES)):
		return false
	var b := _offered(w, P.DEFENSES)
	if b == null:
		return false
	P.add(w, P.standard(P.DEFENSES), mini(b.count, MAX_ITEMS_AT_ONCE), P.Mode.APPEND)
	return true


## `AI_QueueStandardItem2` (not Robotoids, not Cybertrons): a planet of TERRAFORM_MIN_POPULATION
## whose environment is off the race's center on some axis queues up to MAX_ITEMS_AT_ONCE
## terraforming steps, unless some are queued.
static func queue_terraform(w: ClassicWorld, planet: Planet) -> bool:
	if w.personality_id() == ClassicWorld.CYBERTRONS:
		return false
	if planet.population < TERRAFORM_MIN_POPULATION:
		return false
	var e: P.Edit = w.editing
	if e.queued(P.standard(P.TERRAFORM)):
		return false
	var center := w.me().race.hab_center
	var off := false
	for i in 3:
		if absi(planet.environment[i] - center[i]) > 0:
			off = true
	if not off:
		return false
	var b := _offered(w, P.TERRAFORM)
	if b == null:
		return false
	P.add(w, P.standard(P.TERRAFORM), mini(b.count, MAX_ITEMS_AT_ONCE), P.Mode.APPEND)
	b.count = 0
	return true


## `AI_LateGameDefenses`: defenses at each planet with an enemy bomber in orbit.
static func late_game_defenses(w: ClassicWorld) -> void:
	for planet in w.own_planets:
		if _info(w, planet.id, INFO_BOMBERS) != 0:
			planet_defenses(w, planet)


## `AI_PlanetDefenses`: unless defenses are queued, a planet with DEFENSE_MIN_RESOURCES puts
## defenses at the top of its queue: a twenty-fifth of its resources (less a sixth of that above
## 5), as far as the list allows; when a mineral (a fifth of the output, at most 100) allows fewer,
## that many plus one for each DEFENSE_EXTRA_RESOURCES of nine tenths of the resources left after
## alchemy for them, with DEFENSE_ALCHEMY_PER_EXTRA units of alchemy each above them.
static func planet_defenses(w: ClassicWorld, planet: Planet) -> void:
	for q in planet.queue:
		if not q.is_design() and q.item == P.DEFENSES:
			return
	var out := P.output(w, planet)
	if out[3] < DEFENSE_MIN_RESOURCES:
		return
	w.select_planet(planet.id)
	P.open(w)
	var b := _offered(w, P.DEFENSES)
	if b == null:
		P.commit(w, false)
		return
	var ore := 100
	for m in 3:
		ore = mini(ore, out[m] / 5)
	var n := out[3] / 25
	if n > 5:
		n -= out[3] / 25 / 6
	var spare := out[3] - out[3] / 10
	n = mini(n, b.count)
	var alchemy := 0
	if ore < n:
		var unit := P.item_cost(w, planet, P.standard(P.ALCHEMY, 1), true)[3]
		var extra := maxi((spare - unit * ore) / DEFENSE_EXTRA_RESOURCES, 0)
		n = extra + ore
		alchemy = extra * DEFENSE_ALCHEMY_PER_EXTRA
	if n > 0:
		P.add(w, P.standard(P.DEFENSES), n, P.Mode.TOP)
	if alchemy > 0:
		P.add(w, P.standard(P.ALCHEMY), alchemy, P.Mode.TOP)
	P.commit(w, n > 0 or alchemy > 0)


# --- Mines ahead of a waiting item -------------------------------------------------------------


## `AI_FixupMineOrders`, each of the player's planets whose first queue item is not mines,
## alchemy or terraforming and is not begun this year although a year's resources before it
## starts would pay for one unit: as many mines as this year's resources buy (up to the mines
## next year's people can work) go to the top of the queue, or auto alchemy when none, and the
## queue is committed. The original then tries the queue with auto alchemy and with fewer mines
## on its planet copy only, which reaches the world only when that copy is committed later.
static func fixup_mines(w: ClassicWorld) -> void:
	for planet in w.own_planets:
		if planet.queue.is_empty():
			continue
		var top := planet.queue[0]
		if not top.is_design() and top.item in [P.MINES, P.AUTO_ALCHEMY, P.ALCHEMY, P.TERRAFORM]:
			continue
		w.select_planet(planet.id)
		var first := P.completion(w, w.cur_planet, 0)[0]
		if first == 1:
			continue
		if first == -1:
			first = NEVER_FIRST
		var cur := w.cur_planet
		var race := w.me().race
		var cost := P.item_cost(w, cur, cur.queue[0], true)[3]
		var r := PlanetEconomy.resources(cur, race, w.content)
		if not cur.leftover_to_research:
			r -= r * w.me().research_percent / 100
		if cost > (first - 1) * r:
			continue
		var next := PlanetEconomy.next_population(cur, race, w.content)
		var room := maxi(PlanetEconomy.operable_mines(cur, race, w.content, next) - cur.mines, 0)
		var n := room if race.mine_cost * room <= r else r / race.mine_cost
		P.open(w)
		var second := NEVER_LATER
		if n < 1:
			P.add(w, P.standard(P.AUTO_ALCHEMY), 1, P.Mode.TOP)
			P.commit(w, true)
		else:
			P.add(w, P.standard(P.MINES), n, P.Mode.TOP)
			P.commit(w, true)
			second = P.completion(w, w.cur_planet, 1)[0]
			if second == -1:
				second = NEVER_LATER
			var q := w.cur_planet.queue[0]
			q.item = P.AUTO_ALCHEMY
			q.count = 1
		var third := P.completion(w, w.cur_planet, 1)[0]
		if third == -1:
			third = NEVER_LATER
		if (first <= third or second <= third) and n > 0:
			var q := w.cur_planet.queue[0]
			q.item = P.MINES
			if first < second:
				w.cur_planet.queue.remove_at(0)
			else:
				q.count = n


# --- The last pass ------------------------------------------------------------------------------


## `AI_FinishTurn`: every planet of the player (shuffled order) fills its queue.
static func finish_turn(w: ClassicWorld) -> void:
	for planet in w.own_planets:
		w.select_planet(planet.id)
		P.open(w)
		P.commit(w, fill_queue(w, planet))


## `AI_FillPlanetQueue`, with resources to spare after the queue: Macinti terraforms what a
## seventieth of them pays for; otherwise, short of a mineral (and the queue not led by alchemy),
## mines at the top for what is left; with every mineral to spare, factories at the end (as many
## as the germanium and resources pay for) and then mines; mines and factories only up to what the
## people work, less those queued. Once every field is at ALCHEMY_TECH, after turn ALCHEMY_TURN,
## alchemy for the rest (one more), at the top when short of a mineral.
static func fill_queue(w: ClassicWorld, planet: Planet) -> bool:
	var out := P.output(w, planet)
	var cost := P.queue_cost(w, planet)
	var spare: Array[int] = []
	for i in 4:
		spare.append(out[i] - cost[i])
	if spare[3] < 0:
		return false
	var e: P.Edit = w.editing
	var race := w.me().race
	var mines_queued := 0
	var factories_queued := 0
	for q in e.queue:
		if q.item == P.MINES:
			mines_queued += q.count
		elif q.item == P.FACTORIES:
			factories_queued += q.count
	var mines_room := 0
	var factories_room := 0
	var terraform_room := 0
	var mine_cost: Array[int] = [0, 0, 0, 0]
	var factory_cost: Array[int] = [0, 0, 0, 0]
	var alchemy_cost: Array[int] = [0, 0, 0, 0]
	for k in range(e.buildable.size() - 1, -1, -1):
		var b := e.buildable[k]
		match b.item:
			P.MINES:
				var operable := PlanetEconomy.operable_mines(planet, race, w.content)
				var working := PlanetEconomy.effective_mines(planet, race, w.content)
				mines_room = maxi(operable - working - mines_queued, 0)
				mine_cost = P.item_cost(w, planet, b, true)
			P.FACTORIES:
				var operable := PlanetEconomy.operable_factories(planet, race, w.content)
				var working := mini(planet.factories, operable)
				factories_room = maxi(operable - working - factories_queued, 0)
				factory_cost = P.item_cost(w, planet, b, true)
			P.ALCHEMY:
				alchemy_cost = P.item_cost(w, planet, b, true)
			P.TERRAFORM:
				terraform_room = b.count
	if terraform_room > 0 and w.personality_id() == ClassicWorld.MACINTI:
		var steps := mini(terraform_room, (spare[3] + MACINTI_TERRAFORM_RESOURCES - 1) / 70)
		if steps > 0:
			P.add(w, P.standard(P.TERRAFORM), steps, P.Mode.TOP)
			return true
	var short := false
	var factories := 0
	var mines := 0
	if spare[0] < 1 or spare[1] < 1 or spare[2] < 1:
		if not planet.queue.is_empty():
			var top := planet.queue[0]
			if not top.is_design() and (top.item == P.AUTO_ALCHEMY or top.item == P.ALCHEMY):
				return false
		mines = _afford(mines_room, spare[3], mine_cost[3])
		spare[3] -= mine_cost[3] * mines
		short = true
	else:
		var n := factories_room
		if n > 0:
			if not w.state.settings.tutorial:
				n = mini(n, spare[2] / maxi(factory_cost[2], 1))
			else:
				for m in 3:
					n = mini(n, spare[m] / maxi(factory_cost[m], 1))
		factories = _afford(n, spare[3], factory_cost[3])
		spare[3] -= factories * factory_cost[3]
		mines = _afford(mines_room, spare[3], mine_cost[3])
		spare[3] -= mines * mine_cost[3]
	var alchemy := 0
	if (
		alchemy_cost[3] > 0
		and w.me().tech_levels.all(func(t: int) -> bool: return t == ALCHEMY_TECH)
	):
		alchemy = maxi(spare[3] / alchemy_cost[3] + 1, 0)
	if factories > 0:
		P.add(w, P.standard(P.FACTORIES), factories, P.Mode.APPEND)
	if mines > 0:
		P.add(w, P.standard(P.MINES), mines, P.Mode.TOP)
	if alchemy > 0 and w.state.turn > ALCHEMY_TURN:
		P.add(w, P.standard(P.ALCHEMY), alchemy, P.Mode.TOP if short else P.Mode.APPEND)
	return factories + alchemy + mines > 0


## Up to `room` units the resources pay for (none when there is no room).
static func _afford(room: int, resources: int, unit: int) -> int:
	if room < 1:
		return 0
	return mini(room, resources / maxi(unit, 1))
