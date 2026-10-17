class_name ClassicAutomitrons
extends RefCounted
## The original's Automitrons (spec S22 "Automitrons", `AI_Automitrons`): research by plan,
## designs by tech level (`AI_Automitrons_Designs`), freighters, colony ships, mine layers,
## bombers, warships and battleships built at big starbase planets, colony ships on freighter
## hulls settling, bombers going from planet to planet once escorted, and scouts hunting or
## exploring (`AI_DirectFleet`).

const F := preload("res://core/ai/classic/classic_fleets.gd")
const P := preload("res://core/ai/classic/classic_production.gd")

const RESEARCH_PLAN := "ai_research_plan.automitrons"
## Research budget: none before RESEARCH_TURN, then RESEARCH_PCT.
const RESEARCH_TURN := 10
const RESEARCH_PCT := 20
const SPLIT_TURN := 60
## Design slots.
const SCOUT_SLOT := 0
const COLONY_SLOT := 1
const MINE_LAYER_SLOT := 6
const DESTROYER_SLOT := 14
## Slots merged into one fleet (`AI_MergeFleetsByHull`): MERGES_LATE after MERGE_LATE_TURN,
## MERGES_EARLY after MERGE_EARLY_TURN.
const MERGE_LATE_TURN := 50
const MERGES_LATE := [[2, 3, 9, 10, 11, 12], [6]]
const MERGE_EARLY_TURN := 30
const MERGES_EARLY := [[14]]
## Templates (`ai_design_template.<name>`).
const TEMPLATE := "ai_design_template.automitrons_"
## The escort strength a bomber fleet needs before more bombers are built for it, and the
## bombers it then has.
const ESCORT_START := 3
const ESCORT_MAX := 50
const TROOPS_START := 6
const TROOPS_MAX := 12
## Retirement ages: before turn RETIRE_TURNS[i], RETIRE_AGES[i] turns; later the last.
const RETIRE_TURNS := [120, 200]
const RETIRE_AGES := [50, 70, 100]
## Ships are built at starbase planets with this many people (hundreds).
const SHIPYARD_POPULATION := 1500
## Colony ships are built from this turn on.
const COLONY_TURN := 10
## planet_info bytes: "uninhabitable", habitable once terraformed (bit 0x80: people head there),
## "loaded", worth as a target, colony claim.
const INFO_HOSTILE := 2
const INFO_HAB := 3
const INFO_LOADED := 9
const INFO_TARGET := 10
const INFO_COLONY := 15
const MARK := 0x80
## Bombers leave a starbase planet with more than READY_BOMBERS in a bomber slot and more than
## READY_ESCORTS in a battleship slot.
const READY_BOMBERS := 1
const READY_ESCORTS := 2
## A moving fleet with less fuel than LOW_FUEL is scrapped while the scout design has no ram
## scoop.
const LOW_FUEL := 2
const LAY_FOREVER := 5
const COLONISTS_LOADED := 150
const COLONY_SHIP_POPULATION := 200
const BOMBER_WARP := 4
const ALL_TRIES := 5
## Engine tags: no ram scoop (SCOOPLESS); the two cheapest engines (EARLIEST).
const SCOOPLESS := "ai_scoopless_engine"
const EARLIEST := "ai_earliest_engine"

var w: ClassicWorld
var turn := 0
var escort := 0
var troops := 0
var obsolete := []
## Newest designs of the slot groups (-1 none).
var warship := -1
var freighter := -1
var freighter_ships := 0
var bomber := -1
var battleship := -1
## The first of the player's planets (planet order) with a starbase; null without.
var home: Planet = null
## The player's combat fleets and the other players' fleets, the latest listed first.
var own_warships: Array[Fleet] = []
var enemies: Array[Fleet] = []
var _stopped := false


## One turn of Automitrons on world `w`.
static func play(world: ClassicWorld) -> void:
	var t := ClassicAutomitrons.new()
	t.w = world
	t.turn = world.state.turn
	t._play()


func _play() -> void:
	ClassicDesigns.update_starbase_designs(w)
	var station := ClassicDesigns.newer_starbase(w, 0, 5)
	ClassicFreight.plan_depots(w)
	ClassicResearch.follow_plan(w, RESEARCH_PLAN, RESEARCH_PCT if turn >= RESEARCH_TURN else 0)
	if turn > MERGE_LATE_TURN:
		for m: Array in MERGES_LATE:
			F.merge_by_slots(w, m)
	if turn > MERGE_EARLY_TURN:
		for m: Array in MERGES_EARLY:
			F.merge_by_slots(w, m)
	_thresholds()
	_newest()
	if turn > SPLIT_TURN:
		var old := []
		for slot in F.DESIGN_SLOTS:
			if obsolete[slot] != 0:
				old.append(slot)
		F.split_slots(w, old)
	designs(w)
	_planets()
	home = null
	for p in w.state.planets:
		if w.loaded.has(p.id) and p.owner == w.player and p.starbase != null:
			home = p
			break
	for fleet in w.state.fleets.duplicate():
		if fleet.owner != w.player:
			enemies.push_front(fleet)
			continue
		if F.is_combat(w, fleet):
			own_warships.push_front(fleet)
		_first_pass(fleet)
	w.colony_targets_rated = false
	for fleet in w.state.fleets.duplicate():
		if fleet.owner == w.player:
			_last_pass(fleet)
			if _stopped:
				break
	ClassicPlanning.manage(w, station)
	ClassicPlanning.finish_turn(w)


func _thresholds() -> void:
	escort = ESCORT_START
	if turn > 130:
		escort = (turn - 120) / 20 + ESCORT_START
	escort = mini(escort, ESCORT_MAX)
	troops = TROOPS_START
	if turn > 115:
		troops = (turn - 100) / 22 + TROOPS_START
	troops = mini(troops, TROOPS_MAX)


## The newest design of each slot group (`AI_FindDesignForHulls`), retiring old ones.
func _newest() -> void:
	obsolete = []
	obsolete.resize(F.DESIGN_SLOTS)
	obsolete.fill(0)
	var age: int = RETIRE_AGES[-1]
	for i in RETIRE_TURNS.size():
		if turn < RETIRE_TURNS[i]:
			age = RETIRE_AGES[i]
			break
	warship = _group(11, 12, age)
	var f := ClassicDesigns.newest_in_slots(w, 4, 5, age, obsolete)
	freighter = f["slot"]
	freighter_ships = f["remaining"]
	bomber = _group(2, 3, age)
	battleship = _group(9, 10, age)


func _group(low: int, high: int, age: int) -> int:
	return ClassicDesigns.newest_in_slots(w, low, high, age, obsolete)["slot"]


func _tech(field: String) -> int:
	return w.me().tech_levels[PartRules.tech_order(w.content)["tech_field." + field]]


static func _ships(fleet: Fleet, slot: int) -> int:
	var s := fleet.stack_for(slot)
	return 0 if s == null else s.count


## `AI_Automitrons_HasEscortStrength`: ships in slots 11-12 plus twice those in 9-10.
static func strength(fleet: Fleet) -> int:
	return _ships(fleet, 11) + _ships(fleet, 12) + 2 * (_ships(fleet, 9) + _ships(fleet, 10))


# --- Designs -----------------------------------------------------------------------------------


## `AI_Automitrons_Designs`: designs by tech level (spec S22 "Automitrons", the design table).
static func designs(world: ClassicWorld) -> void:
	var me := world.me()
	var order := PartRules.tech_order(world.content)
	var lv := func(field: String) -> int: return me.tech_levels[order["tech_field." + field]]
	var wp: int = lv.call("weapons")
	var pr: int = lv.call("propulsion")
	var co: int = lv.call("construction")
	var el: int = lv.call("electronics")
	var bi: int = lv.call("biotech")
	var empty := func(slot: int) -> bool: return me.ship_design(slot) == null
	var spent := func(slot: int) -> bool:
		return me.ship_design(slot) == null or me.ship_design(slot).remaining == 0
	if empty.call(4) and pr > 4:
		_outfit(world, 4, "freighter_medium")
	if empty.call(5) and pr > 6:
		_outfit(world, 5, "freighter_super")
	if empty.call(DESTROYER_SLOT) and wp > 4 and el > 5 and co > 3 and pr > 4:
		for i in 4:
			world.rng.random(1)
			if _outfit(world, DESTROYER_SLOT, "destroyer"):
				break
	if spent.call(COLONY_SLOT):
		ClassicDesigns.delete(world, COLONY_SLOT, false)
		_outfit(world, COLONY_SLOT, "colony_ship")
	if spent.call(SCOUT_SLOT):
		ClassicDesigns.delete(world, SCOUT_SLOT, false)
		_outfit(world, SCOUT_SLOT, "scout")
	if empty.call(MINE_LAYER_SLOT) and co > 3 and pr > 4 and bi > 5:
		_outfit(world, MINE_LAYER_SLOT, "mine_layer")
	if empty.call(2) and wp > 7 and el > 6 and co > 5 and pr > 6:
		_outfit(world, 2, "bomber_b17")
	if empty.call(3) and wp > 10 and el > 11 and co > 14 and pr > 8:
		_outfit(world, 3, "bomber_b52")
	if empty.call(9) and wp > 4 and el > 5 and co > 12 and pr > 6:
		for i in ALL_TRIES:
			if _outfit(world, 9, "battleship_%d" % world.rng.random(4)):
				break


static func _outfit(world: ClassicWorld, slot: int, template: String) -> bool:
	return ClassicDesigns.outfit(world, slot, TEMPLATE + template)


# --- Planets -----------------------------------------------------------------------------------


## The planet pass over the loaded planets in planet order: planet_info marks and ships at the
## player's big starbase planets.
func _planets() -> void:
	var settle := 0
	for p in w.state.planets:
		if w.loaded.has(p.id) and p.owner == -1 and w.detail[p.id] > 2:
			if F.terraformed_hab(w, p) > 0:
				settle += 1
	for p in w.state.planets:
		if not w.loaded.has(p.id):
			continue
		F.info_set(w, p.id, INFO_LOADED, 1)
		if p.owner == w.player or p.owner == -1:
			if p.owner == w.player and PlanetEconomy.hab_value(p, w.me().race) < 0:
				F.info_set(w, p.id, INFO_HOSTILE, 1)
			elif p.starbase != null and p.population >= SHIPYARD_POPULATION:
				w.select_planet(p.id)
				var e := P.open(w)
				var changed := false
				if not e.queue.any(
					func(q: QueueItem) -> bool: return q.is_design() and not q.starbase
				):
					changed = _queue_ships(p, settle)
				P.commit(w, changed)
		else:
			F.info_set(w, p.id, INFO_TARGET, 2 if p.starbase != null else 1)
			if F.terraformed_hab(w, p) > 0:
				F.info_set(w, p.id, INFO_HAB, 1)


## The ships a starbase planet adds to its open production; whether it added any. `settle` counts
## the unowned planets worth settling.
func _queue_ships(planet: Planet, settle: int) -> bool:
	var me := w.me()
	var changed := false
	var planets := w.state.planets.size()
	var want := maxi(w.planet_count / 10, w.memory[ClassicWorld.DEPOT_COUNT] * 2)
	if (
		_tech("propulsion") > 4
		and freighter != -1
		and (freighter_ships < want or (freighter_ships < want * 10 / 7 and w.rng.random(4) == 0))
	):
		P.add(w, P.ship(freighter), 1, P.Mode.APPEND)
		changed = true
	var colony := me.ship_design(COLONY_SLOT)
	if settle != 0 and colony != null and colony.remaining == 0 and turn > COLONY_TURN:
		P.add(w, P.ship(COLONY_SLOT), 1, P.Mode.APPEND)
		changed = true
	if me.ship_design(MINE_LAYER_SLOT) != null and w.rng.random(3) == 0:
		var n := 0
		for f in w.state.fleets:
			if f.planet == planet.id and _ships(f, MINE_LAYER_SLOT) > 0 and f.owner == w.player:
				n = _ships(f, MINE_LAYER_SLOT)
				break
		if (n < 10 or (n < 17 and w.rng.random(8) == 0)) and w.rng.random(n * 2 + 1) == 0:
			P.add(w, P.ship(MINE_LAYER_SLOT), 3, P.Mode.APPEND)
			changed = true
	if bomber != -1:
		for f in w.state.fleets:
			if f.planet == planet.id and f.owner == w.player and strength(f) >= escort:
				if troops <= _ships(f, 2) + _ships(f, 3):
					P.add(w, P.ship(bomber), 4, P.Mode.APPEND)
					return true
				break
	var groups := [[warship, planets / 12 + 8], [battleship, planets / 24 + 4]]
	for g: Array in groups:
		var slot: int = g[0]
		var d := me.ship_design(slot) if slot != -1 else null
		if d == null or d.remaining >= g[1]:
			continue
		var left := _spare(planet)
		if left.is_empty():
			return changed
		var cost := ProductionCosts.design_cost(d, me, w.content)
		for k in ALL_TRIES:
			for i in 4:
				left[i] -= cost[i]
				if left[i] < 0:
					return changed
			changed = true
			P.add(w, P.ship(slot), 1, P.Mode.APPEND)
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


## The first fleet pass: freighters and colony ships headed for another player's planet drop
## their people there when they could live there and the owner takes drops; otherwise they stop.
func _first_pass(fleet: Fleet) -> void:
	var freight := F.is_freighter(w, fleet)
	if not freight and _ships(fleet, COLONY_SLOT) == 0:
		return
	var target := -1
	if fleet.waypoints.size() < 2:
		target = fleet.planet
	elif fleet.waypoints[1].target == "planet":
		target = fleet.waypoints[1].target_id
	if target == -1:
		return
	var p := w.state.planet(target)
	if p.owner == -1 or p.owner == w.player:
		return
	if (
		(w.planet_info[target] as PackedByteArray)[INFO_HAB] == 0
		or fleet.cargo[Fleet.CARGO_COLONISTS] < 1
		or RaceMath.trait_param(w.state.player(p.owner).race, w.content, "ai.no_colonist_drops", 0)
	):
		_stop(fleet)
		return
	var drop := _drop_waypoint(target, 0)
	w.select_fleet(fleet)
	var here := fleet.waypoints[0]
	if here.target == "planet" and here.target_id == target:
		F.change(w, fleet, 0, drop)
	elif fleet.waypoints.size() > 1:
		F.change(w, fleet, 1, drop)
	_mark(target, INFO_HAB)


## A waypoint to `planet` at `warp` unloading the colonists.
func _drop_waypoint(planet: int, warp: int) -> Waypoint:
	var drop := F.planet_waypoint(w, planet, warp, "transport")
	var cargo := []
	for c in 5:
		cargo.append(
			{"action": "unload_all" if c == Fleet.CARGO_COLONISTS else "none", "amount": 0}
		)
	drop.task_data = {"cargo": cargo}
	return drop


func _mark(planet: int, byte: int) -> void:
	var info: PackedByteArray = w.planet_info[planet]
	F.info_set(w, planet, byte, info[byte] | MARK)


func _stop(fleet: Fleet) -> void:
	F.stop(w, fleet)
	F.clear_task(w, fleet)


func _scrap(fleet: Fleet) -> void:
	F.set_task(w, fleet, "scrap")


## Whether the first part of the design in `slot` has `tag` (no design: as the cheapest engine).
func _engine_has(slot: int, tag: String) -> bool:
	var d := w.me().ship_design(slot)
	if d == null or d.parts.is_empty() or d.parts[0].part.is_empty():
		return true
	return (w.content.part(d.parts[0].part).get("tags", []) as Array).has(tag)


## The last fleet pass, for each of the player's fleets.
func _last_pass(fleet: Fleet) -> void:
	if fleet.waypoints.size() >= 2:
		if _engine_has(SCOUT_SLOT, SCOOPLESS) and fleet.cargo[Fleet.CARGO_FUEL] < LOW_FUEL:
			_scrap(fleet)
		return
	if _ships(fleet, MINE_LAYER_SLOT) > 0:
		if fleet.waypoints.size() == 1 and fleet.waypoints[0].task == "none":
			F.set_task(w, fleet, "lay_mines", {"raw": [LAY_FOREVER, LAY_FOREVER, 0, 0, 0]})
		return
	if _ships(fleet, COLONY_SLOT) > 0:
		_colony_ship(fleet)
	elif F.is_freighter(w, fleet):
		_freighter(fleet)
	elif _ships(fleet, 2) + _ships(fleet, 3) > 0:
		_bombers(fleet)
	elif _ships(fleet, SCOUT_SLOT) > 0:
		if _engine_has(SCOUT_SLOT, SCOOPLESS) and fleet.cargo[Fleet.CARGO_FUEL] < LOW_FUEL:
			_scrap(fleet)
			return
		F.direct_fleet(w, fleet, own_warships, enemies, w.state.settings.computer_alliances, true)


## Colony ships without orders: scrapped unless the colony design is on the template's hull;
## with no people aboard away from the player's well-peopled planets they go home (or are
## scrapped); otherwise they load people where they are and set out to colonize.
func _colony_ship(fleet: Fleet) -> void:
	var d := w.me().ship_design(COLONY_SLOT)
	var hull: String = w.content.get_def("ai_design_template", TEMPLATE + "colony_ship")["hull"]
	if d == null or d.hull != hull:
		_scrap(fleet)
		return
	w.select_fleet(fleet)
	var at: Planet = w.state.planet(fleet.planet) if fleet.planet != -1 else null
	var at_own := at != null and at.owner == w.player
	if (
		(not at_own or at.population < COLONY_SHIP_POPULATION)
		and fleet.cargo[Fleet.CARGO_COLONISTS] == 0
	):
		if (
			(not at_own or at.starbase == null)
			and (_engine_has(COLONY_SLOT, EARLIEST) or not F.return_home(w, fleet, false))
		):
			_scrap(fleet)
		return
	var target: int = F.colony_target(w, fleet, false)["planet"]
	if at_own:
		w.select_fleet(fleet)
		ClassicFreight.move_cargo(
			w, fleet, {"planet": fleet.planet}, Fleet.CARGO_COLONISTS, COLONISTS_LOADED
		)
	if target != -1:
		F.send_to_colonize(w, fleet, target)
		F.info_set(w, target, INFO_COLONY, 4)


## Freighters without orders: a run from their depot (`home` when they have none). With no
## planet to come home to the pass ends here.
func _freighter(fleet: Fleet) -> void:
	if home == null:
		_stopped = true
		return
	var depot := home
	var record := ClassicFreight.depot_of_fleet(w, ClassicWorld.fleet_id(fleet))
	if record >= 0:
		var at := w.state.planet(
			w.memory[ClassicWorld.DEPOT_FIRST + record * ClassicWorld.DEPOT_WORDS]
		)
		if at != null:
			depot = at
	ClassicFreight.plan_transport(w, fleet, depot)


## Bombers without orders: at a starbase planet of the player they wait for bombers and
## battleships; at another player's planet they stay while no combat fleet of another player is
## there; otherwise they head for the target planet rated best from where they are (from `home`
## in deep space, S25 B42).
func _bombers(fleet: Fleet) -> void:
	var from: Planet = home
	if fleet.planet != -1:
		var p := w.state.planet(fleet.planet)
		if p.owner == w.player:
			var ready := (
				(_ships(fleet, 2) > READY_BOMBERS or _ships(fleet, 3) > READY_BOMBERS)
				and (_ships(fleet, 9) > READY_ESCORTS or _ships(fleet, 10) > READY_ESCORTS)
			)
			if p.starbase != null and not ready:
				return
		elif p.owner != -1:
			var guarded := false
			for e in enemies:
				if e.x == fleet.x and e.y == fleet.y and F.is_combat(w, e):
					guarded = true
					break
			if not guarded:
				return
		from = p
	if from == null:
		return
	w.select_fleet(fleet)
	var next: Planet = null
	if w.state.settings.computer_alliances:
		next = F.best_planet(
			w, from.id, func(p: Planet) -> int: return F.target_score(w, from, p, true)
		)
	if next == null:
		next = F.best_planet(
			w, from.id, func(p: Planet) -> int: return F.target_score(w, from, p, false)
		)
	if next == null:
		return
	_mark(next.id, INFO_TARGET)
	F.go(w, fleet, F.planet_waypoint(w, next.id, BOMBER_WARP))
