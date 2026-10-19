class_name ClassicMacintiFleets
extends RefCounted
## Macinti's fleets (spec S22 "Macinti", fleets): colony ships settling, miners mining and moving
## to rich planets (`AI_Macinti_MoveToRichPlanet`), scouts laying mines, freighters moving people
## and minerals (`AI_Macinti_MovePopulation`), and warships invading (`AI_Macinti_Invade`) or
## hunting.

const F := preload("res://core/ai/classic/classic_fleets.gd")
const M := preload("res://core/ai/classic/classic_macinti.gd")

const SCOUT_TURN := 40
const SCRAP_TURN := 11
const WEAK_PEOPLE := 50
const COLONISTS_MAX := 25
const MINER_JOIN := [72, 108]
const SCOUT_JOIN := [72, 108]
const SCOUT_REACH := 105
const WARSHIP_JOIN := [100, 200]
const NUBIAN_JOIN := [36, 72]
const RICH_REACH2 := 5184
const PEOPLE_REACH2 := 40001
const LAY_FOREVER := 5
## Waypoint targets the original files as "other objects".
const OBJECTS := ["minefield", "packet", "wormhole", "trader"]

var m: ClassicMacinti
var w: ClassicWorld


static func direct(brain: ClassicMacinti) -> void:
	var k := ClassicMacintiFleets.new()
	k.m = brain
	k.w = brain.w
	for fleet in brain.w.state.fleets.duplicate():
		if brain.w.state.fleets.has(fleet):
			k._first(fleet)
	for fleet in brain.w.state.fleets.duplicate():
		if (
			fleet.owner == brain.w.player
			and fleet.waypoints.size() < 2
			and F.is_freighter(brain.w, fleet)
		):
			if fleet.battle_plan != 4:
				brain.w.select_fleet(fleet)
				brain.w.order({"type": "fleet_battle_plan", "fleet": fleet.number, "plan": 4})
			k.move_population(fleet)
	for fleet in brain.w.state.fleets.duplicate():
		if fleet.owner == brain.w.player and brain.w.state.fleets.has(fleet):
			k._last(fleet)


## `AI_Macinti_HasEscortStrength`: ships in slots 2-4 plus twice those in 5-7, and when that is
## under the escort strength twice the battleships in slots 8-9; at least the escort (or more
## than it, counting battleships). With `out`, the strength goes to out[0].
static func strong(brain: ClassicMacinti, fleet: Fleet, out: Array = []) -> bool:
	var s := 0
	for slot in [2, 3, 4]:
		s += M.ships(fleet, slot)
	for slot in [5, 6, 7]:
		s += 2 * M.ships(fleet, slot)
	if s < brain.escort:
		var owner := brain.w.state.player(fleet.owner)
		for slot in [8, 9]:
			var d := owner.ship_design(slot)
			if M.ships(fleet, slot) != 0 and d != null and d.hull == M.BATTLESHIP_HULL:
				s += 2 * M.ships(fleet, slot)
		if s <= brain.escort:
			return false
	if not out.is_empty():
		out[0] = s
	return true


func _scrap(fleet: Fleet) -> void:
	F.set_task(w, fleet, "scrap")


func _stop(fleet: Fleet) -> void:
	F.stop(w, fleet)


## The first fleet pass, every fleet in fleet order.
func _first(fleet: Fleet) -> void:
	if fleet.owner != w.player:
		m.enemies.push_front(fleet)
		return
	if fleet.waypoints.size() > 1 and OBJECTS.has(fleet.waypoints[1].target):
		var next := fleet.waypoints[1]
		if F.d2(fleet.x, fleet.y, next.x, next.y) > M.OBJECT_KEEP2:
			_stop(fleet)
	if M.ships(fleet, M.SCOUT_SLOT) < 1 or m.turn <= SCOUT_TURN:
		var miners := M.ships(fleet, 14) > 0 or M.ships(fleet, 15) > 0
		if miners and fleet.waypoints.size() == 1:
			_miners(fleet)
			return
		if F.is_combat(w, fleet):
			m.own_warships.push_front(fleet)
			var armed := false
			for slot in range(2, m.last_warship + 1):
				if M.ships(fleet, slot) > 0:
					armed = true
					break
			var next_planet: bool = (
				fleet.waypoints.size() > 1 and fleet.waypoints[1].target == "planet"
			)
			if armed and (next_planet or fleet.planet != -1):
				var t: int = fleet.waypoints[1].target_id if next_planet else fleet.planet
				var info: PackedByteArray = w.planet_info[t]
				if info[M.INFO_TARGET] != 0:
					F.info_set(w, t, M.INFO_TARGET, info[M.INFO_TARGET] | M.HEADED)
		elif F.is_freighter(w, fleet):
			var t := -1
			if fleet.waypoints.size() < 2 or fleet.waypoints[0].task != "none":
				t = fleet.planet
			elif fleet.waypoints[1].target == "planet":
				t = fleet.waypoints[1].target_id
			if t != -1:
				var p := w.state.planet(t)
				if (p == null or p.owner != w.player) and fleet.cargo[Fleet.CARGO_COLONISTS] == 0:
					_stop(fleet)
					F.clear_task(w, fleet)
		_settle(fleet)
		return
	if fleet.waypoints.size() >= 2:
		if fleet.waypoints[0].task != "none":
			F.clear_task(w, fleet)
		return
	if (
		not (
			m.scout_fleets_at_start < 56 and (m.scout_fleets_at_start < 41 or w.rng.random(3) == 0)
		)
		and F.join_nearest(w, fleet, 0, 0, SCOUT_JOIN[0], SCOUT_JOIN[1])
	):
		return
	if M.ships(fleet, M.SCOUT_SLOT) > 6 and w.rng.random(5) == 0:
		var t := F.random_planet(w, fleet.x, fleet.y, SCOUT_REACH, true)
		if t != -1 and t != fleet.planet:
			F.clear_task(w, fleet)
			F.go(w, fleet, F.planet_waypoint(w, t, M.WARP, "lay_mines"))
			_settle(fleet)
			return
	if fleet.waypoints[0].task == "lay_mines":
		_settle(fleet)
		return
	F.set_task(w, fleet, "lay_mines", {"raw": [LAY_FOREVER, LAY_FOREVER, 0, 0, 0]})


## Miners with no orders: join a miner fleet when there are many; mining, they move to a richer
## planet when this one is poor (and now and then anyway); otherwise they start mining.
func _miners(fleet: Fleet) -> void:
	if (
		(m.miner_fleets > 58 or (m.miner_fleets > 48 and w.rng.random(3) != 0))
		and F.join_nearest(w, fleet, 14, 15, MINER_JOIN[0], MINER_JOIN[1])
	):
		return
	if fleet.waypoints[0].task == "remote_mine":
		if fleet.planet != -1:
			var p := w.state.planet(fleet.planet)
			if p != null and p.owner == w.player:
				var conc: int = p.concentration[0] + p.concentration[1] + p.concentration[2]
				if conc < 30 or (conc < 60 and w.rng.random(3) == 0):
					move_to_rich_planet(fleet)
					return
		if w.rng.random(10) == 0:
			move_to_rich_planet(fleet)
		_settle(fleet)
		return
	F.set_task(w, fleet, "remote_mine")


## The rest of the first pass for a fleet (`LAB_1098_16a1`): early scouts and transports scrap,
## colony ships settle, and the early colony ships of a replaced design go home.
func _settle(fleet: Fleet) -> void:
	if m.turn < SCRAP_TURN and (M.ships(fleet, M.SCOUT_SLOT) > 0 or M.ships(fleet, 2) != 0):
		_scrap(fleet)
		return
	var colonists := M.ships(fleet, M.COLONY_SLOT) != 0
	colonists = colonists or (m.early_colony and M.ships(fleet, M.EARLY_COLONY_SLOT) != 0)
	if fleet.waypoints.size() >= 2:
		if m.early_colony and m.obsolete[M.EARLY_COLONY_SLOT] != 0:
			if M.ships(fleet, M.EARLY_COLONY_SLOT) != 0:
				_stop(fleet)
				F.return_home(w, fleet, false)
		return
	if not colonists:
		return
	if m.early_colony and m.colony_slot == M.COLONY_SLOT and fleet.planet != -1:
		_scrap(fleet)
		return
	if m.level > 1 and fleet.planet != -1:
		var p := w.state.planet(fleet.planet)
		if (
			p != null
			and p.owner != -1
			and p.owner != w.player
			and p.starbase == null
			and p.population_estimate < WEAK_PEOPLE
		):
			return
		if p != null and p.owner == -1:
			if fleet.cargo[Fleet.CARGO_COLONISTS] != 0:
				F.set_task(w, fleet, "colonize")
			else:
				F.return_home(w, fleet, true)
			return
	var pick := F.colony_target(w, fleet, true)
	var target: int = pick["planet"]
	if target == -1 and pick["wormhole"] == null:
		if fleet.planet != -1:
			_scrap(fleet)
		return
	w.select_fleet(fleet)
	if fleet.planet != -1:
		var here := w.state.planet(fleet.planet)
		if here != null and here.owner == w.player:
			var n := mini(here.population / 10, COLONISTS_MAX)
			ClassicFreight.move_cargo(w, fleet, {"planet": here.id}, Fleet.CARGO_COLONISTS, n)
	if target == -1:
		F.send_to_wormhole(w, fleet, pick["wormhole"])
	else:
		F.send_to_colonize(w, fleet, target)


## `AI_Macinti_MoveToRichPlanet`: to the player's planet within 72 light years whose
## concentrations (8 ironium + 10 boranium + 7 germanium) beat this planet's by a fifth.
func move_to_rich_planet(fleet: Fleet) -> bool:
	var best: Planet = null
	var best_score := 0
	var here_score := 0
	for p in w.own_planets:
		if F.d2(fleet.x, fleet.y, p.x, p.y) < RICH_REACH2:
			var score: int = (
				p.concentration[0] * 8 + p.concentration[1] * 10 + p.concentration[2] * 7
			)
			if fleet.planet == p.id:
				here_score = score
			if best_score < score:
				best = p
				best_score = score
	if best == null or here_score * 6 / 5 >= best_score:
		return false
	return F.go(w, fleet, F.planet_waypoint(w, best.id, 6))


## `AI_Macinti_MovePopulation`: a freighter at one of the player's crowded planets takes people to
## the planet near by where they add the most resources (enough more than they make here); else
## it takes a mineral the planet has plenty of to the poorest planet near by in it; else it goes
## to the most crowded planet near by. Returns the planet it heads for, -1 for none.
func move_population(fleet: Fleet) -> int:
	var me := w.me()
	var here: Planet = w.state.planet(fleet.planet) if fleet.planet != -1 else null
	var room := ClassicFreight.cargo_capacity(fleet, me, w.content)
	for c in 3:
		room -= fleet.cargo[c]
	var target: Planet = null
	if here != null and here.owner == w.player and _crowding(here) > 25 and here.population > 999:
		var n := mini(here.population / 20, room)
		if n > 0:
			var made := _resources_with(here, -n)
			var best_gain := 0
			for p in w.own_planets:
				if p == here or (w.planet_info[p.id] as PackedByteArray)[M.INFO_PEOPLE] & 1 != 0:
					continue
				var d := F.d2(fleet.x, fleet.y, p.x, p.y)
				if d >= PEOPLE_REACH2:
					continue
				var loss := 3
				if d >= 22501:
					loss = 12
				elif d >= 10001:
					loss = 9
				elif d >= 2501:
					loss = 6
				var arrive := n - loss * n / 100
				var gain := _resources_with(p, arrive)
				if best_gain < gain:
					best_gain = gain
					target = p
			if (
				target != null
				and made + 5 <= best_gain
				and (made + 10 <= best_gain or m.turn < 81)
				and (made + 15 <= best_gain or m.turn < 161)
			):
				w.select_fleet(fleet)
				ClassicFreight.move_cargo(w, fleet, {"planet": here.id}, Fleet.CARGO_COLONISTS, n)
				var info: PackedByteArray = w.planet_info[target.id]
				F.info_set(w, target.id, M.INFO_PEOPLE, info[M.INFO_PEOPLE] | 1)
				return _go(fleet, target)
			target = null
	if here != null:
		var mineral := 0
		while mineral < 3 and here.surface[mineral] <= 2499:
			mineral += 1
		if mineral < 3:
			var least := 1000
			for p in w.own_planets:
				if p == here:
					continue
				if F.d2(fleet.x, fleet.y, p.x, p.y) < PEOPLE_REACH2 and p.surface[mineral] < least:
					target = p
					least = p.surface[mineral]
			if target != null and least < 200:
				var n := mini(here.surface[mineral] / 5, room)
				w.select_fleet(fleet)
				# the original asks at any planet; only the player's own give it anything
				if n != 0 and here.owner == w.player:
					ClassicFreight.move_cargo(w, fleet, {"planet": here.id}, mineral, n)
				return _go(fleet, target)
			target = null
	var most := 0
	for p in w.own_planets:
		if p == here:
			continue
		var d := F.d2(fleet.x, fleet.y, p.x, p.y)
		if d >= PEOPLE_REACH2:
			continue
		var c := _crowding(p)
		if d >= 22501:
			c -= 6
		elif d >= 10001:
			c -= 4
		elif d >= 2501:
			c -= 2
		if most < c:
			most = c
			target = p
	if target == null:
		return -1
	return _go(fleet, target)


func _go(fleet: Fleet, target: Planet) -> int:
	var wp := F.planet_waypoint(w, target.id, 4, "transport")
	var cargo := []
	for c in 5:
		cargo.append({"action": "unload_all" if c < 4 else "none", "amount": 0})
	wp.task_data = {"cargo": cargo}
	return target.id if F.go(w, fleet, wp) else -1


## `Planet_CapacityPct`: people as a percentage of the maximum, rounded, at most 999.
func _crowding(p: Planet) -> int:
	var most := PlanetEconomy.max_pop(p, w.me().race, w.content)
	if most <= 0:
		return 0
	return mini((most / 2 + p.population * 100) / most, 999)


## A planet's resources with `n` more people (hundreds).
func _resources_with(p: Planet, n: int) -> int:
	var before := PlanetEconomy.resources(p, w.me().race, w.content)
	p.population += n
	var after := PlanetEconomy.resources(p, w.me().race, w.content)
	p.population -= n
	return after - before if n > 0 else before - after


## The last pass: fleets of obsolete designs scrap or go home; warships invade (or join others)
## and other combat fleets hunt, nubians joining nubians when there are many.
func _last(fleet: Fleet) -> void:
	var current := false
	for slot in F.DESIGN_SLOTS:
		if M.ships(fleet, slot) > 0 and m.obsolete[slot] == 0:
			current = true
			break
	if not current:
		if fleet.planet != -1:
			var p := w.state.planet(fleet.planet)
			if p != null and p.owner == w.player and (p.starbase != null or w.rng.random(5) == 0):
				_scrap(fleet)
				return
		var heading := (
			fleet.waypoints.size() >= 2
			and fleet.planet == -1
			and fleet.waypoints[1].target == "planet"
		)
		if heading or F.return_home(w, fleet, false):
			return
	for slot in range(2, 10):
		if M.ships(fleet, slot) < 1 or (slot == M.EARLY_COLONY_SLOT and m.early_colony):
			continue
		if m.warship_fleets < 101 and (m.warship_fleets < 91 or w.rng.random(3) != 0):
			invade(fleet)
			return
		var total := 0
		for k in range(2, 10):
			total += M.ships(fleet, k)
		var r := w.rng.random(100)
		if (
			(r <= total - 10 and w.rng.random(20) != 0)
			or not F.join_nearest(w, fleet, 2, 9, WARSHIP_JOIN[0], WARSHIP_JOIN[1])
		):
			invade(fleet)
		return
	if not F.is_combat(w, fleet):
		return
	if fleet.waypoints.size() >= 2 and fleet.waypoints[1].target == "fleet":
		return
	var join := m.nubian_fleets > (70 if m.turn < 121 else 50)
	if not join and m.nubian_fleets > (60 if m.turn < 121 else 40):
		join = w.rng.random(3) == 0
	if join:
		if (
			(M.ships(fleet, m.nubian) < 20 or w.rng.random(20) == 0)
			and F.join_nearest(w, fleet, 12, 13, NUBIAN_JOIN[0], NUBIAN_JOIN[1])
		):
			return
	F.direct_warship(w, fleet, m.own_warships, m.enemies, w.state.settings.computer_alliances)


## `AI_Macinti_Invade`: as Cybertrons' invasion, with Macinti's strength (S25 B53: the original
## reads an unset strength for a weak fleet) and its bombers in slots 8-9.
func invade(fleet: Fleet) -> void:
	var out := [0]
	if not strong(m, fleet, out):
		var weight := 0
		for slot in [2, 3, 4]:
			weight += M.ships(fleet, slot)
		for slot in [5, 6, 7]:
			weight += 2 * M.ships(fleet, slot)
		out[0] = weight
	var s: int = out[0]
	var t := M.ships(fleet, 8) + M.ships(fleet, 9)
	var escort := m.escort
	var troops := m.troops
	if fleet.waypoints.size() > 1:
		var next := fleet.waypoints[1]
		if F.d2(fleet.x, fleet.y, next.x, next.y) < M.FLEET_KEEP2 or next.target != "fleet":
			if next.target == "fleet":
				return
			if next.target == "planet":
				var p := w.state.planet(next.target_id)
				if p == null:
					return
				if p.owner != -1 and (p.owner != w.player or p.starbase != null):
					return
				if int(w.seen_turn.get(p.id, 0)) != m.turn:
					return
	w.select_fleet(fleet)
	if fleet.planet == -1:
		F.send_to_nearest_enemy(w, fleet, M.SEEK_REACH)
		return
	var here := w.state.planet(fleet.planet)
	var target: Planet = null
	var set_out := false
	if here.owner == w.player:
		if s < escort or t < troops:
			if m.level < 2:
				return
			if s <= escort * 2 and s < 60:
				return
			if w.rng.random(10) > 4 and (s <= escort * 3 or w.rng.random(10) > 6):
				if s < 121 or w.rng.random(10) > 6:
					return
		set_out = true
	elif s < escort >> 1 or t < mini(troops / 2 - 1, 3):
		F.clear_task(w, fleet)
		if (
			m.level > 1
			and (
				(s > escort * 2 and w.rng.random(10) < 5)
				or (s > escort * 4 and w.rng.random(10) < 7)
				or (s > 120 and w.rng.random(10) < 7)
			)
		):
			set_out = true
		else:
			target = F.nearest_planet(
				w,
				here.id,
				func(p: Planet) -> bool: return p.owner == w.player and p.starbase != null
			)
	elif here.owner != -1:
		return
	else:
		set_out = true
	if set_out:
		if w.state.settings.computer_alliances:
			target = F.best_planet(
				w, here.id, func(p: Planet) -> int: return F.target_score(w, here, p, true)
			)
		if target == null:
			target = F.best_planet(
				w, here.id, func(p: Planet) -> int: return F.target_score(w, here, p, false)
			)
	var wp: Waypoint
	if target == null:
		var prey := F.nearest_fleet(w, fleet, func(f: Fleet) -> bool: return f.owner != w.player)
		if prey == null:
			return
		wp = F.fleet_waypoint(prey, M.WARP)
	else:
		var info: PackedByteArray = w.planet_info[target.id]
		F.info_set(w, target.id, M.INFO_TARGET, info[M.INFO_TARGET] | M.HEADED)
		wp = F.planet_waypoint(w, target.id, M.WARP)
	F.go(w, fleet, wp)
