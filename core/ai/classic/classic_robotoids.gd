class_name ClassicRobotoids
extends RefCounted
## The original's Robotoids (spec S22 "Robotoids", `AI_Robotoids`): research by plan, warships
## and bombers kept in design slots by tech level (`AI_Robotoids_Designs`), ships built at
## starbases by what the planet can spare, colony ships, freighter runs, and fleets of warships
## and bombers gathering at home before they set out to invade (`AI_Robotoids_Invade`).

const F := preload("res://core/ai/classic/classic_fleets.gd")
const P := preload("res://core/ai/classic/classic_production.gd")

const RESEARCH_PLAN := "ai_research_plan.robotoids"
const RESEARCH_PCT := 15
const RESEARCH_TURN := 10
const MERGE_TURN := 50
const SPLIT_TURN := 80
## Design slots.
const SCOUT_SLOT := 0
const COLONY_SLOT := 1
const MERGED_SLOTS := [2, 3, 4, 5, 6, 7, 9, 10]
const FREIGHTER_SLOTS := [11, 12, 13]
const WARSHIP_LOW := 14
const WARSHIP_HIGH := 15
## Templates (`ai_design_template.<name>`).
const TEMPLATE := "ai_design_template."
const NUBIAN := "nubian"
const MINE_LAYER := "frigate_mine_layer"
const MUNITIONS := "battleship_munitions"
## The escort strength and bomber count a fleet needs to set out (this turn's thresholds).
const ESCORT_START := 4
const ESCORT_MAX := 50
const BOMBERS_START := 6
const BOMBERS_MAX := 12
## Retirement ages: before turn RETIRE_TURNS[i], RETIRE_AGES[i] turns; later the last.
const RETIRE_TURNS := [120, 200]
const RETIRE_AGES := [50, 70, 100]
## Ships are built at starbase planets with this many people (hundreds).
const SHIPYARD_POPULATION := 200
const COLONY_FLEETS_MAX := 26
const RICH_SURFACE := 5000
## Scouts after this turn lay mines; before SCRAP_TURN they are scrapped.
const SCOUT_TURN := 40
const SCRAP_TURN := 21
const SCOUT_REACH := 105
const OBJECT_REACH2 := 40000
const LAY_FOREVER := 5
## Colony ships load this many (hundreds) where they start.
const COLONISTS_LOADED := 10
const FREIGHTER_PLAN := 4
const WARP := 4
## Invasions.
const FLEET_KEEP2 := 62501
const SEEK_REACH := 150
const DROP_MAX := 30000
const TARGETS := ["minefield", "packet", "wormhole", "trader"]
## planet_info bytes: a target's worth (bit 0x80: a warship heads there) and "another's".
const INFO_WORTH := 10
const INFO_OTHERS := 9
const HEADED := 0x80

var w: ClassicWorld
var turn := 0
var level := 0
var escort := 0
var bombers := 0
var obsolete := []
## Newest designs of the slot groups (-1 none).
var warship := -1
var freighter := -1
var freighter_ships := 0
var bomber := -1
var morph := -1
var battleship := -1
var warship_fleets := 0
var colony := {}
## The player's warships and the other players' fleets, the latest listed first.
var own_warships: Array[Fleet] = []
var enemies: Array[Fleet] = []


## One turn of Robotoids on world `w`.
static func play(world: ClassicWorld) -> void:
	var r := ClassicRobotoids.new()
	r.w = world
	r.turn = world.state.turn
	r.level = world.me().ai_level
	r._play()


func _play() -> void:
	ClassicDesigns.update_starbase_designs(w)
	var station := ClassicDesigns.newer_starbase(w, 0, 5)
	ClassicFreight.plan_depots(w)
	ClassicResearch.follow_plan(w, RESEARCH_PLAN, RESEARCH_PCT if turn >= RESEARCH_TURN else 0)
	if turn > MERGE_TURN:
		F.merge_by_slots(w, MERGED_SLOTS)
		F.merge_by_slots(w, [SCOUT_SLOT])
		F.merge_by_slots(w, [WARSHIP_LOW, WARSHIP_HIGH])
	_thresholds()
	_retire()
	if turn > SPLIT_TURN:
		var old := []
		for slot in F.DESIGN_SLOTS:
			if obsolete[slot] != 0:
				old.append(slot)
		F.split_slots(w, old)
		F.split_slots(w, [SCOUT_SLOT])
		F.split_slots(w, [COLONY_SLOT])
		F.split_slots(w, FREIGHTER_SLOTS)
	designs(w)
	_count()
	_mark_targets()
	for planet in w.own_planets:
		if planet.starbase == null or planet.population < SHIPYARD_POPULATION:
			continue
		w.select_planet(planet.id)
		var e := P.open(w)
		var changed := false
		if not e.queue.any(func(q: QueueItem) -> bool: return q.is_design() and not q.starbase):
			changed = _queue_ships(planet)
		P.commit(w, changed)
	for fleet in w.state.fleets.duplicate():
		_first_pass(fleet)
	_freighters()
	for fleet in w.state.fleets.duplicate():
		if fleet.owner == w.player:
			_last_pass(fleet)
	ClassicPlanning.manage(w, station)
	ClassicPlanning.finish_turn(w)


func _thresholds() -> void:
	escort = ESCORT_START
	if turn > 130:
		escort = (turn - 120) / 20 + ESCORT_START
	escort = mini(escort, ESCORT_MAX)
	bombers = BOMBERS_START
	if turn > 115:
		bombers = (turn - 100) / 22 + BOMBERS_START
	bombers = mini(bombers, BOMBERS_MAX)


## `AI_FindDesignForHulls` for each slot group, all marking one set of obsolete slots.
func _retire() -> void:
	var age: int = RETIRE_AGES[RETIRE_AGES.size() - 1]
	for i in RETIRE_TURNS.size():
		if turn < RETIRE_TURNS[i]:
			age = RETIRE_AGES[i]
			break
	obsolete.resize(F.DESIGN_SLOTS)
	obsolete.fill(0)
	warship = ClassicDesigns.newest_in_slots(w, WARSHIP_LOW, WARSHIP_HIGH, age, obsolete)["slot"]
	var nubian_hull: String = w.content.get_def("ai_design_template", TEMPLATE + NUBIAN)["hull"]
	for slot in [WARSHIP_LOW, WARSHIP_HIGH]:
		var d := w.me().ship_design(slot)
		if obsolete[slot] != 0 and d != null and d.hull == nubian_hull:
			obsolete[slot] = 0
	var found := ClassicDesigns.newest_in_slots(w, 11, 13, age, obsolete)
	freighter = found["slot"]
	freighter_ships = found["remaining"]
	bomber = ClassicDesigns.newest_in_slots(w, 9, 10, age, obsolete)["slot"]
	morph = ClassicDesigns.newest_in_slots(w, 2, 5, age, obsolete)["slot"]
	battleship = ClassicDesigns.newest_in_slots(w, 6, 7, age * 3 / 2, obsolete)["slot"]


func _count() -> void:
	warship_fleets = 0
	if warship != -1:
		for f in w.state.fleets:
			if f.owner == w.player and (F.has_slot(f, WARSHIP_LOW) or F.has_slot(f, WARSHIP_HIGH)):
				warship_fleets += 1
	colony = ClassicFreight.colony_ships(w)


## Other players' planets are worth the population estimate div 250 plus 1 (at most 6), one more
## with a starbase.
func _mark_targets() -> void:
	for p in w.state.planets:
		if p.owner == w.player or p.owner == -1:
			continue
		var worth := mini(p.population_estimate / 250 + 1, 6)
		if p.starbase != null:
			worth += 1
		F.info_set(w, p.id, INFO_WORTH, worth)
		F.info_set(w, p.id, INFO_OTHERS, 1)


# --- Designs -----------------------------------------------------------------------------------


## `AI_Robotoids_Designs`: each empty slot gets its design once the tech allows (S22 table).
static func designs(world: ClassicWorld) -> void:
	var me := world.me()
	var t := world.state.turn
	var order := PartRules.tech_order(world.content)
	var lv := func(field: String) -> int: return me.tech_levels[order["tech_field." + field]]
	var en: int = lv.call("energy")
	var wp: int = lv.call("weapons")
	var pr: int = lv.call("propulsion")
	var co: int = lv.call("construction")
	var el: int = lv.call("electronics")
	var bi: int = lv.call("biotech")
	var needs := [4, 7, 10]
	for k in 3:
		var slot := 11 + k
		if me.ship_design(slot) != null or pr <= 1 or co < needs[k]:
			continue
		if slot != 11 and t - _designed(world, slot - 1) <= 14:
			continue
		if co < 10:
			_outfit(world, slot, "privateer_a" if slot == 11 else "privateer_b")
		else:
			_drawn(world, slot, "meta_morph_freighter_", 6)
	if me.ship_design(WARSHIP_LOW) == null and wp > 4 and el > 5 and co > 5 and pr > 5 and en > 1:
		for i in 5:
			if not _outfit(world, WARSHIP_LOW, NUBIAN):
				if _outfit(world, WARSHIP_LOW, "destroyer_a%d" % world.rng.random(4)):
					break
	if (
		me.ship_design(WARSHIP_HIGH) == null
		and el > 9
		and co > 7
		and pr > 8
		and wp > 13
		and not _outfit(world, WARSHIP_HIGH, NUBIAN)
	):
		_drawn(world, WARSHIP_HIGH, "destroyer_b", 4)
	for slot in [2, 3, 4]:
		if me.ship_design(slot) != null or wp <= 9 or co <= 9 or pr <= 8 or en <= 5:
			continue
		if slot == 2 or _older(world, slot - 1, 12):
			_drawn(
				world, slot, "meta_morph_warship_a" if slot % 2 == 0 else "meta_morph_warship_b", 4
			)
	for slot in [6, 7, 8]:
		if me.ship_design(slot) != null or bi <= 3 or el <= 9 or co <= 11 or pr <= 11:
			continue
		if en <= 5 or wp <= 14:
			continue
		if slot == 6 or _older(world, slot - 1, 20):
			_drawn(world, slot, "battleship_a" if slot == 6 else "battleship_b", 4)
	for slot in [9, 10]:
		if me.ship_design(slot) != null or wp <= 13:
			continue
		if (slot == 9 or _older(world, slot - 1, 15)) and not _outfit(world, slot, MUNITIONS):
			_outfit(world, slot, "b_52_bomber_a" if slot == 9 else "b_52_bomber_b")
	var scout := me.ship_design(SCOUT_SLOT)
	var mine_hull: String = (
		world.content.get_def("ai_design_template", TEMPLATE + MINE_LAYER)["hull"]
	)
	if (
		(scout == null or (scout.hull != mine_hull and scout.remaining == 0))
		and me.ai_level >= 2
		and bi > 3
		and el > 4
		and co > 5
		and pr > 5
		and en > 5
	):
		ClassicDesigns.delete(world, SCOUT_SLOT, false)
		_outfit(world, SCOUT_SLOT, MINE_LAYER)


static func _outfit(world: ClassicWorld, slot: int, template: String) -> bool:
	return ClassicDesigns.outfit(world, slot, TEMPLATE + template)


## Up to five tries, each with a template of the group drawn (`prefix` + 0..count-1).
static func _drawn(world: ClassicWorld, slot: int, prefix: String, count: int) -> void:
	for i in 5:
		if _outfit(world, slot, "%s%d" % [prefix, world.rng.random(count)]):
			return


## When a slot's design was made; an empty slot counts as turn 0.
static func _designed(world: ClassicWorld, slot: int) -> int:
	var d := world.me().ship_design(slot)
	return 0 if d == null else d.turn_designed


## Whether a slot holds a design more than `turns` turns old.
static func _older(world: ClassicWorld, slot: int, turns: int) -> bool:
	var d := world.me().ship_design(slot)
	return d != null and world.state.turn - d.turn_designed > turns


# --- Ships at starbases ------------------------------------------------------------------------


static func _ships(fleet: Fleet, slot: int) -> int:
	var s := fleet.stack_for(slot)
	return 0 if s == null else s.count


## Ships in slots 2-5 plus twice those in 6-7.
static func strength(fleet: Fleet) -> int:
	var n := 0
	for slot in range(2, 6):
		n += _ships(fleet, slot)
	for slot in range(6, 8):
		n += _ships(fleet, slot) * 2
	return n


## Ships in slots 9-10.
static func bomber_count(fleet: Fleet) -> int:
	return _ships(fleet, 9) + _ships(fleet, 10)


## `AI_Robotoids_HasEscortStrength`.
func has_escort_strength(fleet: Fleet) -> bool:
	return strength(fleet) >= escort


## The ships a starbase planet adds to its open production; whether it added any.
func _queue_ships(planet: Planet) -> bool:
	var me := w.me()
	var changed := false
	var depots := w.memory[ClassicWorld.DEPOT_COUNT]
	var want := maxi(w.planet_count / 8, depots * 4)
	if (
		freighter != -1
		and (freighter_ships < want * 8 / 10 or (freighter_ships < want and w.rng.random(3) == 0))
	):
		P.add(w, P.ship(freighter), 1, P.Mode.APPEND)
		changed = true
	var settle: bool = colony["build"]
	if not settle and colony["count"] < COLONY_FLEETS_MAX:
		settle = w.rng.random(depots * 8) == 0
	if settle and turn > 4:
		if turn < SCRAP_TURN:
			P.add(w, P.ship(COLONY_SLOT), 1, P.Mode.APPEND)
		P.add(w, P.ship(COLONY_SLOT), 1, P.Mode.APPEND)
		changed = true
		var race := me.race
		var rate := (
			race.growth_rate
			* RaceMath.trait_param(race, w.content, "race.growth_rate_pct", 100)
			/ 100
		)
		var growth := planet.population * rate
		var resources := PlanetEconomy.resources(planet, race, w.content)
		if growth > 2300 and resources > 35 and level > 0:
			P.add(w, P.ship(COLONY_SLOT), 1, P.Mode.APPEND)
			if growth > 3600 and resources > 50 and level > 1:
				P.add(w, P.ship(COLONY_SLOT), 1, P.Mode.APPEND)
	var mine_hull: String = w.content.get_def("ai_design_template", TEMPLATE + MINE_LAYER)["hull"]
	var scout := me.ship_design(SCOUT_SLOT)
	if scout != null and scout.hull == mine_hull and w.rng.random(4) == 0:
		var n := 0
		for f in w.state.fleets:
			if f.planet == planet.id and _ships(f, SCOUT_SLOT) > 0 and f.owner == w.player:
				n = _ships(f, SCOUT_SLOT)
				break
		if (n < 10 or (n < 17 and w.rng.random(10) == 0)) and w.rng.random(n * 2 + 1) == 0:
			P.add(w, P.ship(SCOUT_SLOT), 4, P.Mode.APPEND)
			changed = true
	# rich: the first surface mineral under RICH_SURFACE is germanium (as the original tests)
	var first_low := 0
	while first_low < 3 and planet.surface[first_low] >= RICH_SURFACE:
		first_low += 1
	var rich := first_low == 2
	if bomber != -1:
		for f in w.state.fleets:
			if f.planet == planet.id and f.owner == w.player and has_escort_strength(f):
				if bomber_count(f) < bombers:
					P.add(w, P.ship(bomber), 6 if rich else 4, P.Mode.APPEND)
					return true
				break
	var planets := w.state.planets.size()
	if morph != -1 and (me.ship_design(morph).remaining < planets / 7 + 6 or w.rng.random(2) != 0):
		var slot := morph
		if battleship != -1 and w.rng.random(2) == 0:
			slot = battleship
		var left := _spare(planet)
		if left.is_empty():
			return changed
		var cost := ProductionCosts.design_cost(me.ship_design(slot), me, w.content)
		var enough := true
		for i in 4:
			# three fifths, in the original's 16-bit arithmetic
			left[i] -= (cost[i] * 3 & 0xFFFF) / 5
			if left[i] < 0:
				enough = false
				break
		if enough:
			P.add(w, P.ship(slot), 5 if rich else 1, P.Mode.APPEND)
			changed = true
	if warship != -1 and me.ship_design(warship).remaining < planets / 12 + 8:
		var left := _spare(planet)
		if left.is_empty():
			return changed
		var cost := ProductionCosts.design_cost(me.ship_design(warship), me, w.content)
		for k in 5:
			for i in 4:
				left[i] -= cost[i]
				if left[i] < 0:
					return changed
			changed = true
			P.add(w, P.ship(warship), 1, P.Mode.APPEND)
	return changed


## This year's output less the cost of the planet's queue as it stands; [] when any is negative.
func _spare(planet: Planet) -> Array[int]:
	var out := P.output(w, planet)
	var cost := P.queue_cost(w, planet)
	for i in 4:
		out[i] -= cost[i]
		if out[i] < 0:
			return []
	return out


# --- Fleets ------------------------------------------------------------------------------------


func _first_pass(fleet: Fleet) -> void:
	if fleet.waypoints.size() > 1:
		var next := fleet.waypoints[1]
		if TARGETS.has(next.target) and F.d2(fleet.x, fleet.y, next.x, next.y) > OBJECT_REACH2:
			F.stop(w, fleet)
	if fleet.owner != w.player:
		enemies.push_front(fleet)
		return
	var scouts := _ships(fleet, SCOUT_SLOT)
	if scouts >= 1 and turn > SCOUT_TURN and fleet.waypoints.size() == 1:
		if scouts > 6 and w.rng.random(5) == 0:
			var pick := F.random_planet(w, fleet.x, fleet.y, SCOUT_REACH, true)
			if pick != -1 and fleet.planet != pick:
				F.clear_task(w, fleet)
				F.go(w, fleet, F.planet_waypoint(w, pick, WARP))
				_colony_ship(fleet)
				return
		if fleet.waypoints[0].task != "none":
			_colony_ship(fleet)
			return
		F.set_task(w, fleet, "lay_mines", {"raw": [LAY_FOREVER, LAY_FOREVER, 0, 0, 0]})
		return
	if F.is_combat(w, fleet):
		own_warships.push_front(fleet)
		if fleet.waypoints[0].task == "lay_mines":
			F.clear_task(w, fleet)
		var armed := false
		for slot in range(2, 8):
			if _ships(fleet, slot) > 0:
				armed = true
				break
		var ahead := -1
		if fleet.waypoints.size() > 1 and fleet.waypoints[1].target == "planet":
			ahead = fleet.waypoints[1].target_id
		elif fleet.planet != -1:
			ahead = fleet.planet
		if armed and ahead != -1:
			var info: PackedByteArray = w.planet_info[ahead]
			if info[INFO_WORTH] != 0:
				F.info_set(w, ahead, INFO_WORTH, info[INFO_WORTH] | HEADED)
	elif F.is_freighter(w, fleet):
		var dest := -1
		if fleet.waypoints.size() < 2 or fleet.waypoints[0].task != "none":
			dest = fleet.planet
		elif fleet.waypoints[1].target == "planet":
			dest = fleet.waypoints[1].target_id
		if dest != -1:
			var p := w.state.planet(dest)
			if (p == null or p.owner != w.player) and fleet.cargo[Fleet.CARGO_COLONISTS] == 0:
				F.stop(w, fleet)
				F.clear_task(w, fleet)
	_colony_ship(fleet)


## Scouts scrapped early; colony ships with nothing to do drop colonists on another player's
## planet (harder levels) or go to their colony target.
func _colony_ship(fleet: Fleet) -> void:
	if turn < SCRAP_TURN and _ships(fleet, SCOUT_SLOT) > 0:
		F.set_task(w, fleet, "scrap")
		return
	if fleet.waypoints.size() >= 2 or _ships(fleet, COLONY_SLOT) == 0:
		return
	if turn <= 4 and w.state.settings.player_positions != "close":
		return
	if level > 1 and fleet.planet != -1:
		var p := w.state.planet(fleet.planet)
		if (
			p != null
			and p.owner != -1
			and p.owner != w.player
			and fleet.cargo[Fleet.CARGO_COLONISTS] > 0
			and not RaceMath.trait_param(
				w.state.player(p.owner).race, w.content, "ai.no_colonist_drops", 0
			)
		):
			var drop := F.planet_waypoint(w, p.id, 0, "transport")
			var cargo := []
			for c in 5:
				cargo.append(
					{"action": "unload_all" if c == Fleet.CARGO_COLONISTS else "none", "amount": 0}
				)
			drop.task_data = {"cargo": cargo}
			F.go(w, fleet, drop)
			var home := F.nearest_planet(w, p.id, _own_starbase)
			if home != null:
				F.go(w, fleet, F.planet_waypoint(w, home.id, WARP))
			return
	var target := F.colony_target(w, fleet)
	if target["planet"] == -1 and target["wormhole"] == null:
		if fleet.planet != -1:
			F.set_task(w, fleet, "scrap")
		return
	w.select_fleet(fleet)
	if fleet.planet != -1:
		ClassicFreight.move_cargo(
			w, fleet, {"planet": fleet.planet}, Fleet.CARGO_COLONISTS, COLONISTS_LOADED
		)
	if target["planet"] == -1:
		F.send_to_wormhole(w, fleet, target["wormhole"])
	else:
		F.send_to_colonize(w, fleet, target["planet"])


func _own_starbase(p: Planet) -> bool:
	return p.owner == w.player and p.starbase != null


## Freighters without orders take the withdrawing battle plan and a run from their depot (the
## first starbase planet when they have none).
func _freighters() -> void:
	var fallback: Planet = null
	for p in w.own_planets:
		if p.starbase != null:
			fallback = p
			break
	if fallback == null:
		return
	for fleet in w.state.fleets.duplicate():
		if fleet.owner != w.player or fleet.waypoints.size() >= 2 or not F.is_freighter(w, fleet):
			continue
		if fleet.battle_plan != FREIGHTER_PLAN:
			w.select_fleet(fleet)
			w.order({"type": "fleet_battle_plan", "fleet": fleet.number, "plan": FREIGHTER_PLAN})
		var record := ClassicFreight.depot_of_fleet(w, ClassicWorld.fleet_id(fleet))
		var home := fallback
		if record >= 0:
			var at := w.state.planet(
				w.memory[ClassicWorld.DEPOT_FIRST + record * ClassicWorld.DEPOT_WORDS]
			)
			if at != null:
				home = at
		ClassicFreight.plan_transport(w, fleet, home)


func _last_pass(fleet: Fleet) -> void:
	var all_old := true
	for slot in F.DESIGN_SLOTS:
		if _ships(fleet, slot) > 0 and obsolete[slot] == 0:
			all_old = false
			break
	if all_old:
		if fleet.planet != -1:
			var p := w.state.planet(fleet.planet)
			if p != null and p.owner == w.player and (p.starbase != null or w.rng.random(5) == 0):
				F.set_task(w, fleet, "scrap")
				return
		if (
			fleet.waypoints.size() > 1
			and fleet.planet == -1
			and fleet.waypoints[1].target == "planet"
		):
			return
		if F.return_home(w, fleet, false):
			return
	for slot in range(2, 11):
		if _ships(fleet, slot) > 0:
			invade(fleet)
			return
	if not F.is_combat(w, fleet):
		return
	if fleet.waypoints.size() > 1 and fleet.waypoints[1].target == "fleet":
		return
	var many := 70 if turn < 121 else 50
	var some := 60 if turn < 121 else 40
	if warship_fleets > many or (warship_fleets > some and w.rng.random(3) == 0):
		if (
			(_ships(fleet, warship) < 20 or w.rng.random(20) == 0)
			and F.join_nearest(w, fleet, WARSHIP_LOW, WARSHIP_HIGH, 36, 72)
		):
			return
	F.direct_warship(w, fleet, own_warships, enemies, w.state.settings.computer_alliances)


# --- Invasions ---------------------------------------------------------------------------------


## `AI_Robotoids_Invade`: a fleet of warships and bombers gathers at home until it has the
## escort and bombers, then sets out for the best target; at another player's planet it drops
## its colonists when they can take it.
func invade(fleet: Fleet) -> void:
	var s := strength(fleet)
	var t := bomber_count(fleet)
	if fleet.waypoints.size() > 1:
		var next := fleet.waypoints[1]
		if F.d2(fleet.x, fleet.y, next.x, next.y) < FLEET_KEEP2 or next.target != "fleet":
			if next.target == "fleet":
				return
			if next.target == "planet":
				var p := w.state.planet(next.target_id)
				if p == null:
					return
				if p.owner != -1 and (p.owner != w.player or p.starbase != null):
					return
				if int(w.seen_turn.get(p.id, 0)) != turn:
					return
	w.select_fleet(fleet)
	if fleet.planet == -1:
		F.send_to_nearest_enemy(w, fleet, SEEK_REACH)
		return
	var here := w.state.planet(fleet.planet)
	var target: Planet = null
	var set_out := false
	if here.owner == w.player and here.starbase != null:
		if s < escort or t < bombers:
			if level < 2:
				return
			if s <= escort * 2 and s < 60:
				return
			if w.rng.random(10) > 4 and (s <= escort * 3 or w.rng.random(10) > 6):
				if s < 121 or w.rng.random(10) > 6:
					return
		else:
			# the troops come from the selected planet copy
			var pop := w.cur_planet.population
			var n := 0
			if pop > 3000:
				n = pop / 10
			elif pop > 2000:
				n = pop / 15
			elif pop > 1000:
				n = pop / 20
			if n > 0:
				ClassicFreight.move_cargo(
					w, fleet, {"planet": fleet.planet}, Fleet.CARGO_COLONISTS, n
				)
		set_out = true
	elif s >= escort >> 1 and t >= mini(bombers / 2 - 1, 3):
		if here.owner != -1 and here.owner != w.player:
			_drop(fleet, here)
			return
		if here.owner == w.player and here.population > 1000:
			ClassicFreight.move_cargo(
				w, fleet, {"planet": fleet.planet}, Fleet.CARGO_COLONISTS, here.population / 5
			)
		set_out = true
	else:
		F.clear_task(w, fleet)
		if (
			level > 1
			and (
				(s > escort * 2 and w.rng.random(10) < 5)
				or (s > escort * 4 and w.rng.random(10) < 7)
				or (s > 120 and w.rng.random(10) < 7)
			)
		):
			set_out = true
		else:
			target = F.nearest_planet(w, here.id, _own_starbase)
	if set_out:
		if w.state.settings.computer_alliances:
			target = F.best_planet(w, here.id, func(p: Planet) -> int: return score(here, p, true))
		if target == null:
			target = F.best_planet(w, here.id, func(p: Planet) -> int: return score(here, p, false))
	var wp: Waypoint
	if target == null:
		var prey := F.nearest_fleet(w, fleet, func(f: Fleet) -> bool: return f.owner != w.player)
		if prey == null:
			return
		wp = F.fleet_waypoint(prey, WARP)
	else:
		var info: PackedByteArray = w.planet_info[target.id]
		F.info_set(w, target.id, INFO_WORTH, info[INFO_WORTH] | HEADED)
		wp = F.planet_waypoint(w, target.id, WARP)
	F.go(w, fleet, wp)


## At another player's planet: drops colonists when the troops aboard can take it.
func _drop(fleet: Fleet, here: Planet) -> void:
	var aboard := fleet.cargo[Fleet.CARGO_COLONISTS]
	# divisions truncate toward zero, as the original's
	var needed := here.population_estimate * 400 / ((-1 - here.defense_estimate) * 18 / 4 + 100)
	if aboard / 5 <= needed and (needed >= 200 or aboard < 351):
		if needed > 9 or aboard < 151:
			return
	var n := mini(mini(maxi(aboard / 2, needed * 5 / 4), aboard), DROP_MAX)
	ClassicFreight.move_cargo(w, fleet, {"planet": here.id}, Fleet.CARGO_COLONISTS, -n)


## `AI_ScoreColonyTarget` (`spare_computers`) and `AI_ScoreColonyTarget2` (ClassicFleets): a
## planet's worth as an invasion target from `from`.
func score(from: Planet, p: Planet, spare_computers: bool) -> int:
	return F.target_score(w, from, p, spare_computers)
