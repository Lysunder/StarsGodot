class_name ClassicRototills
extends RefCounted
## The original's Rototills (spec S22 "Rototills", `AI_Rototills`): no designs of their own and no
## research plan (the lowest field), colony ships built at big starbase planets one a turn,
## colony ships settling (through wormholes too), freighter runs, miners moving to rich planets,
## bombers going from planet to planet, and scouts hunting or exploring (`AI_DirectFleet`).

const F := preload("res://core/ai/classic/classic_fleets.gd")
const P := preload("res://core/ai/classic/classic_production.gd")

## Research budget: none before RESEARCH_TURN, then RESEARCH_PCT; no plan.
const RESEARCH_TURN := 20
const RESEARCH_PCT := 15
## Design slots.
const SCOUT_SLOT := 0
const COLONY_SLOT := 1
## Ships are built at starbase planets with this many people (hundreds).
const SHIPYARD_POPULATION := 1000
## planet_info bytes: mining worth (bit 0x80: a miner heads there), "uninhabitable", habitable
## once terraformed (bit 0x80: people head there), "loaded", worth as a target, colony claim.
const INFO_MINING := 1
const INFO_HOSTILE := 2
const INFO_HAB := 3
const INFO_LOADED := 9
const INFO_TARGET := 10
const INFO_COLONY := 15
const MARK := 0x80
## Bombers leave a starbase planet with more than READY_BOMBERS in a bomber slot.
const READY_BOMBERS := 1
## A scout fleet with less fuel than LOW_FUEL is scrapped when the scout design's engine is the
## starting scout's (SCOUT_ENGINE).
const LOW_FUEL := 2
const SCOUT_ENGINE := "ai_starting_scout_engine"
## Colony ships whose design has one of these engines don't look for wormholes, and when stranded
## are scrapped.
const EARLIEST := "ai_earliest_engine"
const COLONISTS_LOADED := 25
const COLONY_SHIP_POPULATION := 50
const BOMBER_WARP := 4
const MINER_WARP := 6
const MINING_POOR := 4

var w: ClassicWorld
var turn := 0
## The first of the player's planets (planet order) with a starbase; null without.
var home: Planet = null
## The player's fleets with warship hulls and the other players' fleets, the latest listed first.
var own_warships: Array[Fleet] = []
var enemies: Array[Fleet] = []
## A colony ship was added at some planet this turn.
var _colony_queued := false
var _stopped := false


## One turn of Rototills on world `w`.
static func play(world: ClassicWorld) -> void:
	var t := ClassicRototills.new()
	t.w = world
	t.turn = world.state.turn
	t._play()


func _play() -> void:
	ClassicDesigns.update_starbase_designs(w)
	var station := ClassicDesigns.newer_starbase(w, 0, 5)
	ClassicFreight.plan_depots(w)
	ClassicResearch.follow_plan(w, "", RESEARCH_PCT if turn >= RESEARCH_TURN else 0)
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


static func _ships(fleet: Fleet, slot: int) -> int:
	var s := fleet.stack_for(slot)
	return 0 if s == null else s.count


static func _miners(fleet: Fleet) -> bool:
	return _ships(fleet, 7) + _ships(fleet, 8) > 0


# --- Planets -----------------------------------------------------------------------------------


## The planet pass over the loaded planets in planet order: planet_info marks and colony ships at
## the player's big starbase planets.
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
		if p.owner == -1 and w.detail[p.id] > 2:
			F.info_set(w, p.id, INFO_MINING, ClassicTurindrones._mining_worth(p))
		if p.owner == w.player or p.owner == -1:
			if p.owner == w.player and PlanetEconomy.hab_value(p, w.me().race) < 0:
				F.info_set(w, p.id, INFO_HOSTILE, 1)
			elif p.starbase != null and p.population >= SHIPYARD_POPULATION:
				w.select_planet(p.id)
				var e := P.open(w)
				var changed := false
				# a starbase design past the first starbase slot in the queue
				if not e.queue.any(
					func(q: QueueItem) -> bool: return q.is_design() and q.starbase and q.design > 0
				):
					changed = _queue_ships(settle)
				P.commit(w, changed)
		else:
			F.info_set(w, p.id, INFO_TARGET, 2 if p.starbase != null else 1)
			if F.terraformed_hab(w, p) > 0:
				F.info_set(w, p.id, INFO_HAB, 1)


## The ships a starbase planet adds to its open production; whether the queue is to be given.
## `settle` counts the unowned planets worth settling. On turn 0 two scouts are added but not
## given (as the original). Otherwise one colony ship a turn, when the colony design has no ships
## or fewer than `settle` less one.
func _queue_ships(settle: int) -> bool:
	if turn == 0:
		P.add(w, P.ship(SCOUT_SLOT), 1, P.Mode.APPEND)
		P.add(w, P.ship(SCOUT_SLOT), 1, P.Mode.APPEND)
		return false
	if _colony_queued:
		return false
	var colony := w.me().ship_design(COLONY_SLOT)
	var have := 0 if colony == null else colony.remaining
	if have != 0 and settle <= have + 1:
		return false
	_colony_queued = true
	P.add(w, P.ship(COLONY_SLOT), 1, P.Mode.APPEND)
	return true


# --- Fleets ------------------------------------------------------------------------------------


## The first fleet pass: miners mark the planet they mine (and stop at a planet someone owns);
## freighters and colony ships headed for another player's planet drop their people there when
## they could live there and the owner takes drops, otherwise they stop.
func _first_pass(fleet: Fleet) -> void:
	if _miners(fleet):
		var id := -1
		if fleet.planet == -1:
			if fleet.waypoints.size() < 2 or fleet.waypoints[1].target != "planet":
				return
			id = fleet.waypoints[1].target_id
		else:
			if w.state.planet(fleet.planet).owner != -1:
				_stop(fleet)
				return
			id = fleet.planet
		_mark(id, INFO_MINING)
		return
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
	var drop := F.planet_waypoint(w, target, 0, "transport")
	var cargo := []
	for c in 5:
		cargo.append(
			{"action": "unload_all" if c == Fleet.CARGO_COLONISTS else "none", "amount": 0}
		)
	drop.task_data = {"cargo": cargo}
	w.select_fleet(fleet)
	var here := fleet.waypoints[0]
	if here.target == "planet" and here.target_id == target:
		F.change(w, fleet, 0, drop)
	elif fleet.waypoints.size() > 1:
		F.change(w, fleet, 1, drop)
	_mark(target, INFO_HAB)


func _mark(planet: int, byte: int) -> void:
	var info: PackedByteArray = w.planet_info[planet]
	F.info_set(w, planet, byte, info[byte] | MARK)


func _stop(fleet: Fleet) -> void:
	F.stop(w, fleet)
	F.clear_task(w, fleet)


func _scrap(fleet: Fleet) -> void:
	F.set_task(w, fleet, "scrap")


## Whether the first part of the design in `slot` has `tag`.
func _engine_has(slot: int, tag: String) -> bool:
	var d := w.me().ship_design(slot)
	if d == null or d.parts.is_empty() or d.parts[0].part.is_empty():
		return false
	return (w.content.part(d.parts[0].part).get("tags", []) as Array).has(tag)


## The last fleet pass, for each of the player's fleets.
func _last_pass(fleet: Fleet) -> void:
	if _miners(fleet):
		_miner(fleet)
		return
	if fleet.waypoints.size() >= 2:
		return
	if _ships(fleet, COLONY_SLOT) > 0:
		_colony_ship(fleet)
	elif F.is_freighter(w, fleet):
		_freighter(fleet)
	elif _ships(fleet, 13) + _ships(fleet, 14) > 0:
		_bombers(fleet)
	elif _ships(fleet, SCOUT_SLOT) > 0:
		w.select_fleet(fleet)
		if _engine_has(SCOUT_SLOT, SCOUT_ENGINE) and fleet.cargo[Fleet.CARGO_FUEL] < LOW_FUEL:
			_scrap(fleet)
			return
		F.direct_fleet(w, fleet, own_warships, enemies, w.state.settings.computer_alliances, true)


## Miners at a planet worth less than MINING_POOR move on (appended) to the planet the random
## mining score rates best, which is marked; the old planet's worth is cleared.
func _miner(fleet: Fleet) -> void:
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


## `Pred_AI_RandomTarget`, as for Turindrones.
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
## they go home (or are scrapped); otherwise they load people where they are and set out to
## colonize, or into a wormhole.
func _colony_ship(fleet: Fleet) -> void:
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
	var pick := F.colony_target(w, fleet, not _engine_has(COLONY_SLOT, EARLIEST))
	if at_own:
		w.select_fleet(fleet)
		ClassicFreight.move_cargo(
			w, fleet, {"planet": fleet.planet}, Fleet.CARGO_COLONISTS, COLONISTS_LOADED
		)
	var target: int = pick["planet"]
	if target != -1:
		F.send_to_colonize(w, fleet, target)
		F.info_set(w, target, INFO_COLONY, 4)
	elif pick["wormhole"] != null:
		F.send_to_wormhole(w, fleet, pick["wormhole"])


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


## Bombers without orders: at a starbase planet of the player they wait for more bombers; at
## another player's planet they stay while no combat fleet of another player is there; otherwise
## they head for the target planet rated best from where they are (from `home` in deep space, S25
## B42).
func _bombers(fleet: Fleet) -> void:
	w.select_fleet(fleet)
	var from: Planet = home
	if fleet.planet != -1:
		var p := w.state.planet(fleet.planet)
		if p.owner == w.player:
			var ready := _ships(fleet, 13) > READY_BOMBERS or _ships(fleet, 14) > READY_BOMBERS
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
