class_name ClassicTurindrones
extends RefCounted
## The original's Turindrones (spec S22 "Turindrones", `AI_Turindrones`): research by plan,
## designs by tech level (`AI_Turindrones_Designs`), scouts, colony ships, freighters, miners and
## mine layers built at starbase planets, warships and battleships by what the planet can spare,
## warships hunting or exploring (`AI_DirectFleet`), bombers going from planet to planet, colony
## ships dropping people on other players' undefended planets, and miners moving to rich planets.

const F := preload("res://core/ai/classic/classic_fleets.gd")
const P := preload("res://core/ai/classic/classic_production.gd")

const RESEARCH_PLAN := "ai_research_plan.turindrones"
const RESEARCH_PCT := 15
const SPLIT_TURN := 60
## Design slots.
const SCOUT_SLOT := 0
const COLONY_SLOT := 1
const MINE_LAYER_SLOT := 12
const RAIDER_SLOT := 15
## Slots merged into one fleet when the first of them has a design (`AI_MergeFleetsByHull`).
const MERGES := [[13, [4, 5, 6, 7, 13, 14, 15]], [12, [12]], [10, [10, 11]], [2, [2, 3]]]
## Templates (`ai_design_template.<name>`).
const TEMPLATE := "ai_design_template.turindrones_"
## A scout of this hull (the starting scout) is scrapped once construction passes 5; the
## colony slot's design on this hull is not deleted before a new one is made (as the original).
const STARTING_SCOUT_HULL := "hull.scout"
const KEPT_COLONY_HULL := "hull.privateer"
## The escort strength a bomber fleet needs to leave a starbase, and the bombers it then has.
const ESCORT_START := 3
const ESCORT_MAX := 50
const TROOPS_START := 6
const TROOPS_MAX := 12
## Retirement ages: before turn RETIRE_TURNS[i], RETIRE_AGES[i] turns; later the last.
const RETIRE_TURNS := [120, 200]
const RETIRE_AGES := [50, 70, 100]
## Ships are built at starbase planets with this many people (hundreds); fewer leave only the
## leftover to research.
const SHIPYARD_POPULATION := 200
## planet_info bytes: mining worth (bit 0x80: a miner heads there), "another player's planet"
## (worth as a target), habitability once terraformed, "uninhabitable", "loaded".
const INFO_MINING := 1
const INFO_HOSTILE := 2
const INFO_HAB := 3
const INFO_LOADED := 9
const INFO_TARGET := 10
const INFO_COLONY := 15
const MARK := 0x80
## A mineral concentration from this counts MINING_RICH; below it half. The worth is at most
## MINING_MAX; a miner leaves a planet worth less than MINING_POOR.
const MINING_CONC := 67
const MINING_RICH := 75
const MINING_MAX := 127
const MINING_POOR := 4
## Planets a turn-0 scout covers: SCOUTED_SMALL each while fewer than SCOUTS_BIG are left.
const SCOUTED_SMALL := 30
const SCOUTED_BIG := 100
const SCOUTS_BIG := 191
const SCOUTS_MAX := 32
const LAY_FOREVER := 5
const COLONISTS_LOADED := 25
const COLONY_SHIP_POPULATION := 50
const BOMBER_WARP := 4
const DROP_WARP := 6
const MINER_WARP := 6
const ALL_TRIES := 5

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
var raider := -1
var destroyer := -1
## The first of the player's planets with a starbase (else the last of them; null without).
var home: Planet = null
## The player's fleets with warship hulls and the other players' fleets, the latest listed first.
var own_warships: Array[Fleet] = []
var enemies: Array[Fleet] = []
var _stopped := false


## One turn of Turindrones on world `w`.
static func play(world: ClassicWorld) -> void:
	var t := ClassicTurindrones.new()
	t.w = world
	t.turn = world.state.turn
	t._play()


func _play() -> void:
	ClassicDesigns.update_starbase_designs(w)
	var station := ClassicDesigns.newer_starbase(w, 0, 5)
	ClassicFreight.plan_depots(w)
	ClassicResearch.follow_plan(w, RESEARCH_PLAN, RESEARCH_PCT)
	for m: Array in MERGES:
		if w.me().ship_design(m[0]) != null:
			F.merge_by_slots(w, m[1])
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
	for p in w.own_planets:
		home = p
		if p.starbase != null:
			break
	for fleet in w.state.fleets.duplicate():
		if fleet.owner != w.player:
			enemies.push_front(fleet)
			continue
		if F.has_warship_hull(w, fleet):
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
	warship = _group(6, 7, age)
	var f := ClassicDesigns.newest_in_slots(w, 8, 9, age, obsolete)
	freighter = f["slot"]
	freighter_ships = f["remaining"]
	bomber = _group(13, 14, age)
	battleship = _group(4, 5, age)
	_group(MINE_LAYER_SLOT, MINE_LAYER_SLOT, age)
	raider = _group(RAIDER_SLOT, RAIDER_SLOT, age)
	if _tech("construction") >= 7:
		_group(2, 3, age)
	destroyer = _group(10, 11, age)


func _group(low: int, high: int, age: int) -> int:
	return ClassicDesigns.newest_in_slots(w, low, high, age, obsolete)["slot"]


func _tech(field: String) -> int:
	return w.me().tech_levels[PartRules.tech_order(w.content)["tech_field." + field]]


static func _ships(fleet: Fleet, slot: int) -> int:
	var s := fleet.stack_for(slot)
	return 0 if s == null else s.count


# --- Designs -----------------------------------------------------------------------------------


## `AI_Turindrones_Designs`: designs by tech level (spec S22 "Turindrones", the design table).
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
	if empty.call(8) and pr > 4 and co > 7:
		_outfit(world, 8, "freighter_rogue")
	if empty.call(9) and pr > 6 and co > 10:
		_outfit(world, 9, "freighter_galleon")
	if empty.call(10) and wp > 4 and el > 4 and co > 3 and pr > 4:
		for i in 4:
			world.rng.random(1)
			if _outfit(world, 10, "destroyer"):
				break
	if spent.call(COLONY_SLOT):
		var d := me.ship_design(COLONY_SLOT)
		if d != null and d.hull != KEPT_COLONY_HULL:
			ClassicDesigns.delete(world, COLONY_SLOT, false)
		_outfit(world, COLONY_SLOT, "colony_ship")
	if spent.call(SCOUT_SLOT):
		ClassicDesigns.delete(world, SCOUT_SLOT, false)
		_outfit(world, SCOUT_SLOT, "scout")
	if spent.call(2) and co > 6 and el > 3:
		ClassicDesigns.delete(world, 2, false)
		_outfit(world, 2, "miner")
	if spent.call(MINE_LAYER_SLOT) and co > 3 and bi > 3:
		_outfit(world, MINE_LAYER_SLOT, "mine_layer")
	if empty.call(13) and wp > 7 and el > 6 and co > 5:
		_outfit(world, 13, "bomber")
	if empty.call(14) and wp > 10 and el > 11 and co > 14 and pr > 8:
		_outfit(world, 14, "bomber")
	if empty.call(4) and wp > 4 and el > 5 and co > 12 and pr > 6:
		for i in ALL_TRIES:
			if _outfit(world, 4, "battleship_%d" % world.rng.random(4)):
				break
	if empty.call(RAIDER_SLOT) and wp > 4 and el > 5 and co > 12 and pr > 6:
		# the original makes it five times over, each replacing the last
		for i in ALL_TRIES:
			_outfit(world, RAIDER_SLOT, "freighter_rogue")


static func _outfit(world: ClassicWorld, slot: int, template: String) -> bool:
	return ClassicDesigns.outfit(world, slot, TEMPLATE + template)


# --- Planets -----------------------------------------------------------------------------------


## The planet pass over the loaded planets in planet order: planet_info marks, the leftover-to-
## research setting of the player's small planets, and ships at its starbase planets.
func _planets() -> void:
	var settle := 0
	for p in w.state.planets:
		if w.loaded.has(p.id) and p.owner == -1 and w.detail[p.id] > 2:
			if F.terraformed_hab(w, p) > 0:
				settle += 1
	var others := 0
	for p in w.state.planets:
		if not w.loaded.has(p.id):
			continue
		F.info_set(w, p.id, INFO_LOADED, 1)
		if p.owner == -1 and w.detail[p.id] > 2:
			F.info_set(w, p.id, INFO_MINING, _mining_worth(p))
		if p.owner == w.player:
			if PlanetEconomy.hab_value(p, w.me().race) < 0:
				F.info_set(w, p.id, INFO_HOSTILE, 1)
			elif p.starbase == null or p.population < SHIPYARD_POPULATION:
				_leftover(p, p.population < SHIPYARD_POPULATION)
			else:
				w.select_planet(p.id)
				var e := P.open(w)
				var changed := false
				if not e.queue.any(
					func(q: QueueItem) -> bool: return q.is_design() and not q.starbase
				):
					changed = _queue_ships(p, settle, others)
				P.commit(w, changed)
		elif p.owner != -1:
			F.info_set(w, p.id, INFO_TARGET, 2 if p.starbase != null else 1)
			var hab := F.terraformed_hab(w, p)
			if hab > 0:
				F.info_set(w, p.id, INFO_HAB, hab)
				others += 1


## Each mineral's concentration halved, or MINING_RICH from MINING_CONC, added up (at most
## MINING_MAX).
static func _mining_worth(p: Planet) -> int:
	var worth := 0
	for c in p.concentration:
		worth += c >> 1 if c < MINING_CONC else MINING_RICH
	return mini(worth, MINING_MAX)


## Sets a planet's "contribute only leftover resources to research" when it changes.
func _leftover(p: Planet, value: bool) -> void:
	w.select_planet(p.id)
	if p.leftover_to_research == value:
		return
	p.leftover_to_research = value
	(
		w
		. order(
			{
				"type": "planet_settings",
				"planet": p.id,
				"leftover_to_research": value,
				"mass_driver_target": p.mass_driver_target,
				"mass_driver_warp": p.mass_driver_warp,
				"route": p.route,
			}
		)
	)


## The ships a starbase planet adds to its open production; whether it added any. `settle` counts
## the unowned planets worth settling, `others` the other players' planets the people could live
## on that the planet pass has met so far.
func _queue_ships(planet: Planet, settle: int, others: int) -> bool:
	var me := w.me()
	var changed := false
	var planets := w.state.planets.size()
	if turn == 0:
		var n := planets
		while n > 0:
			P.add(w, P.ship(SCOUT_SLOT), 1, P.Mode.APPEND)
			changed = true
			n -= SCOUTED_SMALL if n < SCOUTS_BIG else SCOUTED_BIG
	else:
		var scout := me.ship_design(SCOUT_SLOT)
		var scout_hull: String = w.content.get_def("ai_design_template", TEMPLATE + "scout")["hull"]
		if scout != null and scout.hull == scout_hull:
			var cap := mini(planets / 4, SCOUTS_MAX)
			if scout.remaining < cap and scout.built / 10 < scout.remaining:
				P.add(w, P.ship(SCOUT_SLOT), 1, P.Mode.APPEND)
				changed = true
	var want := maxi(w.planet_count / 10, w.memory[ClassicWorld.DEPOT_COUNT] * 2)
	if (
		_tech("propulsion") > 4
		and freighter != -1
		and (freighter_ships < want or (freighter_ships < want * 10 / 7 and w.rng.random(4) == 0))
	):
		P.add(w, P.ship(freighter), 1, P.Mode.APPEND)
		changed = true
	var colony := me.ship_design(COLONY_SLOT)
	if (settle != 0 or others != 0) and colony != null and colony.remaining < 2:
		for i in 4:
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
			if f.planet == planet.id and f.owner == w.player and _escorted(f):
				if troops <= _ships(f, 13) + _ships(f, 14):
					P.add(w, P.ship(bomber), 4, P.Mode.APPEND)
					return true
				break
	var groups := [
		[battleship, planets / 24 + 4],
		[warship, planets / 12 + 8],
		[destroyer, planets / 4 + 12],
		[raider, planets / 12 + 8],
	]
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


## `AI_Robotoids_HasEscortStrength`: ships in slots 2-5 plus twice those in 6-7, at least
## the escort strength.
func _escorted(fleet: Fleet) -> bool:
	return ClassicRobotoids.strength(fleet) >= escort


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


## The first fleet pass: colony ships and freighters at other players' planets drop their people
## or stop; miners with a task keep mining.
func _first_pass(fleet: Fleet) -> void:
	var miners := _ships(fleet, 2) + _ships(fleet, 3) > 0
	if miners and fleet.waypoints[-1].task != "none":
		_keep_mining(fleet)
		return
	var target := -1
	if _ships(fleet, 8) == 0 and _ships(fleet, 9) == 0:
		if _ships(fleet, COLONY_SLOT) == 0:
			return
		if fleet.waypoints.size() < 2:
			target = fleet.planet
		elif fleet.waypoints[1].target == "planet":
			target = fleet.waypoints[1].target_id
		if target == -1:
			return
		if (w.planet_info[target] as PackedByteArray)[INFO_HAB] != 0:
			_drop_or_stop(fleet, target)
			return
		var p := w.state.planet(target)
		if p.owner != -1 and p.owner != w.player:
			_stop(fleet)
		return
	if fleet.waypoints.size() < 2:
		target = fleet.planet
	elif fleet.waypoints[1].target == "planet":
		target = fleet.waypoints[1].target_id
	_drop_or_stop(fleet, target)


## Miners with a task: in deep space the next waypoint becomes remote mining; at a planet another
## player has taken they stop. The planet mined is marked.
func _keep_mining(fleet: Fleet) -> void:
	var id := -1
	if fleet.planet == -1:
		if fleet.waypoints.size() < 2:
			return
		var wp := fleet.waypoints[1].copy() as Waypoint
		wp.task = "remote_mine"
		if not wp.task_data.has("raw"):
			wp.task_data = F.empty_task_data(wp.task)
		w.select_fleet(fleet)
		F.change(w, fleet, 1, wp)
		id = wp.target_id
	else:
		if w.state.planet(fleet.planet).owner != -1:
			_stop(fleet)
			return
		id = fleet.planet
	if id >= 0:
		_mark(id, INFO_MINING)


## A fleet headed for `target` (-1 none): in deep space it stops; at another player's planet it
## drops its people there when they could live there, the owner takes drops and the planet has no
## starbase, then heads home; otherwise it stops.
func _drop_or_stop(fleet: Fleet, target: int) -> void:
	if target == -1:
		if fleet.waypoints.size() > 1 and fleet.waypoints[1].target == "none":
			_stop(fleet)
		return
	var p := w.state.planet(target)
	if p.owner == -1 or p.owner == w.player:
		return
	if (
		(w.planet_info[target] as PackedByteArray)[INFO_HAB] == 0
		or fleet.cargo[Fleet.CARGO_COLONISTS] < 1
		or RaceMath.trait_param(w.state.player(p.owner).race, w.content, "ai.no_colonist_drops", 0)
		or p.starbase != null
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
	F.return_home(w, fleet, false)


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


## The last fleet pass, for the player's fleets without orders.
func _last_pass(fleet: Fleet) -> void:
	if _ships(fleet, 2) + _ships(fleet, 3) > 0:
		_miner(fleet)
		return
	if fleet.waypoints.size() >= 2:
		return
	if _ships(fleet, COLONY_SLOT) > 0:
		_colony_ship(fleet)
	elif _ships(fleet, 8) + _ships(fleet, 9) > 0:
		_freighter(fleet)
	elif _ships(fleet, 13) + _ships(fleet, 14) > 0:
		_bombers(fleet)
	elif _ships(fleet, SCOUT_SLOT) + _ships(fleet, 10) + _ships(fleet, 11) > 0:
		var scout := w.me().ship_design(SCOUT_SLOT)
		if (
			_ships(fleet, SCOUT_SLOT) > 0
			and _tech("construction") > 5
			and scout != null
			and scout.hull == STARTING_SCOUT_HULL
		):
			_scrap(fleet)
			return
		F.direct_fleet(w, fleet, own_warships, enemies, w.state.settings.computer_alliances, true)
	elif (
		_ships(fleet, MINE_LAYER_SLOT) > 0
		and fleet.waypoints.size() == 1
		and fleet.waypoints[0].task == "none"
	):
		F.set_task(w, fleet, "lay_mines", {"raw": [LAY_FOREVER, LAY_FOREVER, 0, 0, 0]})


## Miners at a planet worth less than MINING_POOR move on (appended) to the planet the random
## mining score rates best, which is marked; the old planet's worth is cleared.
func _miner(fleet: Fleet) -> void:
	if turn == 0:
		_scrap(fleet)
		return
	if fleet.planet == -1:
		return
	w.select_fleet(fleet)
	var here := fleet.planet
	if (w.planet_info[here] as PackedByteArray)[INFO_MINING] >= MINING_POOR:
		return
	var from := w.state.planet(here)
	var next := F.best_planet(w, here, func(p: Planet) -> int: return _mining_score(from, p))
	if next == null:
		return
	F.go_after(w, fleet, F.planet_waypoint(w, next.id, MINER_WARP, "remote_mine"))
	_mark(next.id, INFO_MINING)
	var info: PackedByteArray = w.planet_info[here]
	F.info_set(w, here, INFO_MINING, info[INFO_MINING] & MARK)


## `Pred_AI_RandomTarget`: a planet's mining worth (with its mark), one a miner heads for only on
## a draw of 25 in 100 (drawn for every planet with a worth).
func _mining_score(from: Planet, p: Planet) -> int:
	if p == from:
		return 0
	var worth: int = (w.planet_info[p.id] as PackedByteArray)[INFO_MINING]
	if worth == 0:
		return 0
	if w.rng.random(100) < 25 or worth & MARK == 0:
		return worth
	return 0


## Colony ships without orders: with no people aboard away from the player's well-peopled planets
## they go home (or are scrapped); otherwise they load people at home and set out to colonize, or
## to drop them on another player's planet.
func _colony_ship(fleet: Fleet) -> void:
	var at: Planet = w.state.planet(fleet.planet) if fleet.planet != -1 else null
	var at_own := at != null and at.owner == w.player
	if (
		(not at_own or at.population < COLONY_SHIP_POPULATION)
		and fleet.cargo[Fleet.CARGO_COLONISTS] == 0
	):
		if (
			(not at_own or at.starbase == null)
			and (_starter_engine() or not F.return_home(w, fleet, false))
		):
			_scrap(fleet)
		return
	var pick := F.colony_target(w, fleet, false)
	var from: Planet = home
	if at_own:
		w.select_fleet(fleet)
		ClassicFreight.move_cargo(
			w, fleet, {"planet": fleet.planet}, Fleet.CARGO_COLONISTS, COLONISTS_LOADED
		)
		from = at
	var target: int = pick["planet"]
	if target != -1:
		F.send_to_colonize(w, fleet, target)
		F.info_set(w, target, INFO_COLONY, 4)
		return
	if from == null:
		return
	var drop := F.nearest_planet(w, from.id, func(p: Planet) -> bool: return _colonizable(from, p))
	if drop != null:
		_mark(drop.id, INFO_TARGET)
		F.go(w, fleet, _drop_waypoint(drop.id, DROP_WARP))


## Whether the colony slot's design has a starter engine in its first slot.
func _starter_engine() -> bool:
	var d := w.me().ship_design(COLONY_SLOT)
	if d == null or d.parts.is_empty() or d.parts[0].part.is_empty():
		return false
	return (w.content.part(d.parts[0].part).get("tags", []) as Array).has(F.STARTER_ENGINE)


## `Pred_AI_Colonizable`: another player's planet without a starbase the people could live on,
## whose owner takes drops.
func _colonizable(from: Planet, p: Planet) -> bool:
	if p == from:
		return false
	var info: PackedByteArray = w.planet_info[p.id]
	if info[INFO_TARGET] != 1 or info[INFO_HAB] == 0:
		return false
	return not RaceMath.trait_param(
		w.state.player(p.owner).race, w.content, "ai.no_colonist_drops", 0
	)


## Freighters without orders: scrapped on turn 0; otherwise a run from their depot (`home` when
## they have none). With no planet to come home to the pass ends here.
func _freighter(fleet: Fleet) -> void:
	if turn == 0:
		_scrap(fleet)
		return
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


## Bombers without orders: at a starbase planet of the player they wait for the bombers and the
## escort; at another player's planet they stay while no warship of another player is there;
## otherwise they head for the target planet rated best from where they are (or from `home` in
## deep space).
func _bombers(fleet: Fleet) -> void:
	var from: Planet = home
	if fleet.planet != -1:
		var p := w.state.planet(fleet.planet)
		if p.owner == w.player:
			var ready := (
				troops <= _ships(fleet, 13) + _ships(fleet, 14)
				and escort / 2 <= _ships(fleet, 4) + _ships(fleet, 5)
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
