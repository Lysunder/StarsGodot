class_name ClassicFleets
extends RefCounted
## How the classic personalities move their fleets (spec S22 "Classic fleets"): what a fleet is,
## new orders (`AI_AddWaypoint` and its callers), merging and splitting, safe speeds in
## minefields, warships' targets (`AI_DirectWarship`) and colony ships' (`AI_RateColonyTargets`).

const COMBAT := "ai_hull_class.combat"
const ESCORT := "ai_hull_class.escort"
const MULTIROLE := "ai_hull_class.multirole"
const FREIGHTER := "ai_hull_class.freighter"
const CARGO_MORPH := "ai_hull_class.cargo_morph"
const COLONY := "ai_hull_class.colony"
## Cargo room (kT) that makes a multirole ship a freighter.
const CARGO_SHIP_ROOM := 500
## Speeds the toolkit's orders go at (the minefield pass sets most fleets' speeds afterwards).
const WARP_HOME := 4
const WARP_JOIN := 6
const DESIGN_SLOTS := 16
## AI_MergeFleetsByHull keeps at most this many fleets to merge into per pass.
const MERGE_LIST := 32
## No fleet is split once the player has this many.
const SPLIT_LIMIT := 501
## A warship's prey within this distance squared is chased; beyond it, planets.
const CHASE_RANGE2 := 32400
## Minefield safe speeds (`AI_SetMinefieldSafeWarp`).
const MINE_WARP_HEAVY := 6
const MINE_WARP_STANDARD := 4
const MINE_WARP_SPEED_BUMP := 5
## Colony ships look through wormholes only before this turn.
const WORMHOLE_TURN := 120
const NEAR_START := 10000000
## Planet_info byte 15 for a planet the player's turn file doesn't hold (not Robotoids or Macinti).
const UNSEEN := 0x10
## Hull class of `AI_HasWarshipHull` (scout to dreadnought).
const WARSHIP := "ai_hull_class.warship"
## planet_info byte rating a planet as a target (`AI_ScoreColonyTarget`), and its "a warship heads
## there" bit.
const INFO_TARGET := 10
const HEADED := 0x80
## `AI_ChooseColonyTarget` looks for a wormhole on a draw of this many in 100.
const WORMHOLE_PCT := 5
## AI_HasNearbyUnclaimedPlanet's turn and distances (light years).
const UNCLAIMED_TURN := 60
const UNCLAIMED_NEAR := 250
const UNCLAIMED_MID := 300
const UNCLAIMED_FAR := 350
## Engines that make a stranded colony ship not worth bringing home (Turindrones).
const STARTER_ENGINE := "ai_starter_engine"
const WARSHIP_START := 1000000


static func hulls_of(w: ClassicWorld, class_id: String) -> Array:
	return w.content.get_def("ai_hull_class", class_id)["hulls"]


static func _rating(w: ClassicWorld, owner: int, slot: int) -> int:
	return int(w.ratings.get("%d/%d" % [owner, slot], 0))


## The fleet's ships by design slot (count > 0), slot order.
static func stacks_of(fleet: Fleet) -> Array[ShipStack]:
	var out: Array[ShipStack] = []
	for slot in DESIGN_SLOTS:
		var s := fleet.stack_for(slot)
		if s != null and s.count > 0:
			out.append(s)
	return out


static func ships(fleet: Fleet) -> int:
	var n := 0
	for s in fleet.stacks:
		n += s.count
	return n


static func has_slot(fleet: Fleet, slot: int) -> bool:
	var s := fleet.stack_for(slot)
	return s != null and s.count > 0


# --- What a fleet is ---------------------------------------------------------------------------


## `AI_IsCombatFleet`, design slots in order: warship hulls make a combat fleet; the first escort
## hull decides by its rating (above 0); a multirole hull with less than CARGO_SHIP_ROOM of cargo
## and a rating counts.
static func is_combat(w: ClassicWorld, fleet: Fleet) -> bool:
	var owner := w.state.player(fleet.owner)
	for s in stacks_of(fleet):
		var d := owner.ship_design(s.design)
		if hulls_of(w, COMBAT).has(d.hull):
			return true
		if hulls_of(w, ESCORT).has(d.hull):
			return _rating(w, fleet.owner, s.design) > 0
		if (
			hulls_of(w, MULTIROLE).has(d.hull)
			and PartRules.cargo_capacity(d, w.content) < CARGO_SHIP_ROOM
			and _rating(w, fleet.owner, s.design) > 0
		):
			return true
	return false


## `AI_IsFreighterFleet`: a freighter hull, or a cargo morph with CARGO_SHIP_ROOM of cargo and a
## rating.
static func is_freighter(w: ClassicWorld, fleet: Fleet) -> bool:
	var owner := w.state.player(fleet.owner)
	for s in stacks_of(fleet):
		var d := owner.ship_design(s.design)
		if hulls_of(w, FREIGHTER).has(d.hull):
			return true
		if (
			hulls_of(w, CARGO_MORPH).has(d.hull)
			and PartRules.cargo_capacity(d, w.content) >= CARGO_SHIP_ROOM
			and _rating(w, fleet.owner, s.design) > 0
		):
			return true
	return false


# --- Orders ------------------------------------------------------------------------------------


static func planet_waypoint(w: ClassicWorld, id: int, warp: int, task: String = "none") -> Waypoint:
	var p := w.state.planet(id)
	var wp := Waypoint.new(p.x, p.y)
	wp.target = "planet"
	wp.target_id = id
	wp.warp = warp
	wp.task = task
	wp.task_data = empty_task_data(task)
	return wp


## The task data an order carries for `task` when nothing is set: none without a task, five zero
## words for the tasks other than transport (as the original stores its waypoints).
static func empty_task_data(task: String) -> Dictionary:
	if task == "none" or task == "transport":
		return {}
	return {"raw": [0, 0, 0, 0, 0]}


static func fleet_waypoint(target: Fleet, warp: int) -> Waypoint:
	var wp := Waypoint.new(target.x, target.y)
	wp.target = "fleet"
	wp.target_owner = target.owner
	wp.target_id = target.number
	wp.warp = warp
	return wp


## New orders (`AI_AddWaypoint`): a waypoint where the fleet is replaces its orders; elsewhere it
## follows the fleet's current place. Given as waypoint orders; false when refused.
static func go(w: ClassicWorld, fleet: Fleet, wp: Waypoint) -> bool:
	stop(w, fleet)
	var here := fleet.waypoints[0]
	var reason := ""
	if here.x == wp.x and here.y == wp.y:
		reason = w.order(
			{"type": "waypoint_change", "fleet": fleet.number, "index": 0, "waypoint": wp.to_dict()}
		)
	else:
		reason = w.order(
			{"type": "waypoint_add", "fleet": fleet.number, "index": 1, "waypoint": wp.to_dict()}
		)
	return reason.is_empty()


## Drops the fleet's waypoints beyond where it is (the original's waypoint count set to 1).
static func stop(w: ClassicWorld, fleet: Fleet) -> void:
	w.select_fleet(fleet)
	while fleet.waypoints.size() > 1:
		var n := mini(fleet.waypoints.size() - 1, 2)
		w.order({"type": "waypoint_delete", "fleet": fleet.number, "index": 1, "count": n})


## Changes the fleet's waypoint `index` (given as an order).
static func change(w: ClassicWorld, fleet: Fleet, index: int, wp: Waypoint) -> void:
	w.order(
		{"type": "waypoint_change", "fleet": fleet.number, "index": index, "waypoint": wp.to_dict()}
	)


## `AI_ClearTask`: no task at the fleet's current place.
static func clear_task(w: ClassicWorld, fleet: Fleet) -> void:
	w.select_fleet(fleet)
	var wp := fleet.waypoints[0].copy() as Waypoint
	wp.task = "none"
	wp.task_data = {}
	change(w, fleet, 0, wp)


## Gives waypoint 0 a task (the original's in-place edit of the current waypoint), and with
## `data` its task data (else the data stays).
static func set_task(w: ClassicWorld, fleet: Fleet, task: String, data: Dictionary = {}) -> void:
	w.select_fleet(fleet)
	var wp := fleet.waypoints[0].copy() as Waypoint
	wp.task = task
	if not data.is_empty():
		wp.task_data = data.duplicate(true)
	elif not wp.task_data.has("raw"):
		wp.task_data = empty_task_data(task)
	change(w, fleet, 0, wp)


## `AI_SendToPlanet`: to colonize a planet at the fleet's top speed (no easing).
static func send_to_colonize(w: ClassicWorld, fleet: Fleet, planet_id: int) -> bool:
	var top := Retargeting.default_warp(fleet, w.me(), w.content, false)
	return go(w, fleet, planet_waypoint(w, planet_id, top, "colonize"))


## `AI_SendToPoint`: into a wormhole at the fleet's top speed (no easing).
static func send_to_wormhole(w: ClassicWorld, fleet: Fleet, hole: Wormhole) -> bool:
	var wp := Waypoint.new(hole.x, hole.y)
	wp.target = "wormhole"
	wp.target_id = hole.number
	wp.warp = Retargeting.default_warp(fleet, w.me(), w.content, false)
	return go(w, fleet, wp)


## `AI_NearestHomePlanet`: the nearest of the player's planets with a starbase (with more than
## 250 hundred people when `peopled`) to where the fleet is; -1 for none.
static func nearest_home(w: ClassicWorld, fleet: Fleet, peopled: bool) -> int:
	var here := fleet.waypoints[0]
	var best := -1
	var best_d := NEAR_START
	for p in w.state.planets:
		var d := d2(here.x, here.y, p.x, p.y)
		if d < best_d and p.owner == w.player and p.starbase != null:
			if not peopled or p.population > 250:
				best = p.id
				best_d = d
	return best


## `AI_ReturnHome`: to the nearest home planet at WARP_HOME; false when there is none.
static func return_home(w: ClassicWorld, fleet: Fleet, peopled: bool) -> bool:
	var home := nearest_home(w, fleet, peopled)
	if home < 0:
		return false
	return go(w, fleet, planet_waypoint(w, home, WARP_HOME))


## `AI_SendToNearestObject`: to the nearest planet of another player within `reach` at
## WARP_HOME, unless the fleet is there.
static func send_to_nearest_enemy(w: ClassicWorld, fleet: Fleet, reach: int) -> void:
	var here := fleet.waypoints[0]
	var best: Planet = null
	var best_d := NEAR_START
	for p in w.state.planets:
		var d := d2(here.x, here.y, p.x, p.y)
		if d < best_d and p.owner != w.player and p.owner != -1:
			best = p
			best_d = d
	var target := -1
	if best != null and best_d <= reach * reach:
		target = best.id
	else:
		var at := WaypointWarp.planet_at(w.state, fleet.x, fleet.y)
		if at == null:
			return
		target = at.id
	if fleet.planet != target:
		go(w, fleet, planet_waypoint(w, target, WARP_HOME))


static func d2(x1: int, y1: int, x2: int, y2: int) -> int:
	return (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)


## `AI_FindNearestPlanet`: the nearest planet to planet `from_id` that `accept` takes (asked only
## of planets nearer than the best so far); null for none.
static func nearest_planet(w: ClassicWorld, from_id: int, accept: Callable) -> Planet:
	var from := w.state.planet(from_id)
	var best: Planet = null
	var best_d := NEAR_START
	for p in w.state.planets:
		var d := d2(from.x, from.y, p.x, p.y)
		if d < best_d and accept.call(p):
			best = p
			best_d = d
	return best


## `AI_HasNearbyUnclaimedPlanet`: before turn UNCLAIMED_TURN always; later by the distance from
## `planet` to the nearest planet planet_info byte 13 leaves clear: within UNCLAIMED_NEAR light
## years yes, beyond UNCLAIMED_FAR no, between on draws of 1 in 2 (one past UNCLAIMED_MID, another
## past UNCLAIMED_NEAR).
static func has_nearby_unclaimed(w: ClassicWorld, planet: Planet) -> bool:
	if w.state.turn < UNCLAIMED_TURN:
		return true
	var best := 10000000
	for p in w.state.planets:
		if (w.planet_info[p.id] as PackedByteArray)[13] == 0:
			var d := d2(planet.x, planet.y, p.x, p.y)
			if d < best:
				best = d
	if best > UNCLAIMED_FAR * UNCLAIMED_FAR:
		return false
	if best > UNCLAIMED_MID * UNCLAIMED_MID and w.rng.random(2) != 0:
		return false
	if best > UNCLAIMED_NEAR * UNCLAIMED_NEAR and w.rng.random(2) != 0:
		return false
	return true


## `AI_FindNearestPlanet2`: the planet `score` rates highest (every planet is rated, in order;
## at least 1), the nearer of equals; null for none.
static func best_planet(w: ClassicWorld, from_id: int, score: Callable) -> Planet:
	var from := w.state.planet(from_id)
	var best: Planet = null
	var best_score := 1
	var best_d := NEAR_START
	for p in w.state.planets:
		var d := d2(from.x, from.y, p.x, p.y)
		var s: int = score.call(p)
		if best_score < s or (best_score == s and d < best_d):
			best = p
			best_score = s
			best_d = d
	return best


## `AI_FindNearestFleet`: the nearest fleet (in fleet order) that `accept` takes (asked only of
## fleets nearer than the best so far); null for none.
static func nearest_fleet(w: ClassicWorld, from: Fleet, accept: Callable) -> Fleet:
	var best: Fleet = null
	var best_d := NEAR_START
	for f in w.state.fleets:
		var d := d2(from.x, from.y, f.x, f.y)
		if d < best_d and accept.call(f):
			best = f
			best_d = d
	return best


## `AI_PickRandomTarget`: one of the planets within `reach` of (x, y), each as likely (one draw
## per planet in reach); with `avoid_starbases` drawn again up to twice while the pick has a
## starbase. -1 for none.
static func random_planet(
	w: ClassicWorld, x: int, y: int, reach: int, avoid_starbases: bool
) -> int:
	var tries := 2 if avoid_starbases else 0
	while true:
		var seen := 1
		var pick := -1
		for p in w.state.planets:
			if d2(x, y, p.x, p.y) <= reach * reach:
				var r := w.rng.random(seen)
				seen += 1
				if r == 0:
					pick = p.id
		if pick == -1 or tries < 1:
			return pick
		tries -= 1
		if w.state.planet(pick).starbase == null:
			return pick
	return -1


## `AI_Explore`: the nearest of the player's fleets before this one (fleet order) with ships in
## slots `low`..`high`; when within `near` (or `far`, on a draw of 1 in 2) the fleet clears its
## task and joins it at WARP_JOIN. False when it does not.
static func join_nearest(
	w: ClassicWorld, fleet: Fleet, low: int, high: int, near: int, far: int
) -> bool:
	var best: Fleet = null
	var best_d := 9999999
	for f in w.state.fleets:
		if f.owner != w.player:
			continue
		if f == fleet:
			break
		for slot in range(low, high + 1):
			if has_slot(f, slot):
				var d := d2(fleet.x, fleet.y, f.x, f.y)
				if d < best_d:
					best = f
					best_d = d
				break
	if best == null:
		return false
	if best_d > near * near and (best_d > far * far or w.rng.random(2) == 0):
		return false
	clear_task(w, fleet)
	return go(w, fleet, fleet_waypoint(best, WARP_JOIN))


# --- Merging and splitting ---------------------------------------------------------------------


## `AI_MergeFleetsByHull`: the player's fleets with ships in the design slots of `slots` merge
## with the first such fleet at the same place, in fleet order (all its ships move over as a ship
## move, S11, so cargo and damage follow as for one); up to MERGE_LIST fleets are kept
## to merge into, then another pass starts where the list ran out. A merged fleet leaves the
## fleet list, so the fleet after it is passed over.
static func merge_by_slots(w: ClassicWorld, slots: Array) -> void:
	if slots.is_empty():
		return
	var kept: Array[Fleet] = []
	var resume := -1
	var i := 0
	while true:
		if i >= w.state.fleets.size():
			if resume < 0:
				return
			i = resume
			resume = -1
			kept.clear()
		var f := w.state.fleets[i]
		if f.owner == w.player and slots.any(func(s: int) -> bool: return has_slot(f, s)):
			var into: Fleet = null
			for k in kept:
				if k.planet == f.planet and k.x == f.x and k.y == f.y:
					into = k
					break
			if into != null:
				# MergeFleets: all ships move as a ship move (S11), not as a merge order
				var moved := []
				for st in stacks_of(f):
					moved.append({"design": st.design, "count": st.count})
				(
					w
					. order(
						{
							"type": "fleet_move_ships",
							"fleet": into.number,
							"other": f.number,
							"ships": moved,
						}
					)
				)
			elif kept.size() == MERGE_LIST:
				if resume < 0:
					resume = i
			else:
				kept.append(f)
		i += 1
	return


## `AI_SplitFleets`: while the player has fewer than SPLIT_LIMIT fleets, the first fleet (fleet
## order) with ships both in the slots of `slots` and in others splits them off into a new fleet
## (cargo and fuel following the ships, S11).
static func split_slots(w: ClassicWorld, slots: Array) -> void:
	if slots.is_empty():
		return
	while w.state.fleets_of(w.player).size() < SPLIT_LIMIT:
		var found: Fleet = null
		for f in w.state.fleets:
			if f.owner != w.player or ships(f) == 0:
				continue
			var listed := false
			var other := false
			for s in stacks_of(f):
				if slots.has(s.design):
					listed = true
				else:
					other = true
			if listed and other:
				found = f
				break
		if found == null:
			return
		w.select_fleet(found)
		var before := w.state.fleets_of(w.player)
		if not w.order({"type": "fleet_split", "fleet": found.number}).is_empty():
			return
		var created: Fleet = null
		for f in w.state.fleets_of(w.player):
			if not before.has(f):
				created = f
		var moved := []
		for s in stacks_of(found):
			if slots.has(s.design):
				moved.append({"design": s.design, "count": s.count})
		(
			w
			. order(
				{
					"type": "fleet_move_ships",
					"fleet": created.number,
					"other": found.number,
					"ships": moved,
				}
			)
		)


# --- Speeds in minefields ----------------------------------------------------------------------


## `AI_AvoidMinefieldsAll`: every fleet of the player with somewhere to go gets its next speed:
## inside a known minefield of another player (not a speed bump), heavy fields MINE_WARP_HEAVY,
## standard MINE_WARP_STANDARD or on a draw (6 in 10) MINE_WARP_SPEED_BUMP, one more with
## `minefield.speed_bonus`; elsewhere the default warp (WaypointWarp, as a computer player).
static func avoid_minefields(w: ClassicWorld) -> void:
	var fields: Array[Minefield] = []
	for field in w.state.minefields:
		if field.owner != w.player and field.type != "speed_bump":
			fields.append(field)
	for fleet in w.state.fleets.duplicate():
		if fleet.owner != w.player or fleet.waypoints.size() < 2:
			continue
		var inside: Minefield = null
		for field in fields:
			if d2(fleet.x, fleet.y, field.x, field.y) < int(w.minefield_scale[field]):
				inside = field
				break
		w.select_fleet(fleet)
		var warp: int
		if inside == null:
			warp = WaypointWarp.default_warp(w.state, w.content, fleet, 1, true)
		else:
			if inside.type == "heavy":
				warp = MINE_WARP_HEAVY
			else:
				warp = MINE_WARP_STANDARD
				if w.rng.random(10) >= 4:
					warp = MINE_WARP_SPEED_BUMP
			warp += RaceMath.trait_param(w.me().race, w.content, "minefield.speed_bonus", 0)
		if fleet.waypoints[1].warp != warp:
			var wp := fleet.waypoints[1].copy() as Waypoint
			wp.warp = warp
			change(w, fleet, 1, wp)


# --- Warships ----------------------------------------------------------------------------------


## `AI_DirectWarship`: a warship's target. Among `enemies` (other players' fleets, in the order
## given; with `spare_computers` not computer players') the nearest one is chosen, passing over
## (on a draw of 1 in 3) one that `own` fleets already chase, and (on a draw of 14 in 15) keeping
## one they chase with more than a fifth of this fleet's ships. Within CHASE_RANGE2 the fleet
## chases it. With none at all and `spare_computers`, computer players' fleets count after all.
## Otherwise, low on fuel (under half) it goes home; failing that, to the planet nearest the prey
## that none of `own` heads for; failing that, the nearest planet of another player; failing
## that, the nearest planet planet_info byte 9 does not mark (any planet, drawn, if none). A fleet
## already heading for a planet keeps going (-1); otherwise the new orders go at WARP_HOME
## (0, or -1 when refused).
static func direct_warship(
	w: ClassicWorld, fleet: Fleet, own: Array[Fleet], enemies: Array[Fleet], spare_computers: bool
) -> int:
	var n := ships(fleet)
	var best: Fleet = null
	var best_d := WARSHIP_START
	for e in enemies:
		if spare_computers and w.is_computer(e.owner):
			continue
		var chasing := 0
		for o in own:
			if o == fleet or o.waypoints.size() < 2:
				continue
			var next := o.waypoints[1]
			if (
				next.target == "fleet"
				and next.target_owner == e.owner
				and next.target_id == e.number
			):
				chasing += ships(o)
		if chasing > 0 and w.rng.random(3) == 0:
			continue
		if n < chasing * 5 and w.rng.random(15) == 0:
			continue
		var d := d2(e.x, e.y, fleet.x, fleet.y)
		if d < best_d:
			best = e
			best_d = d
	var wp: Waypoint = null
	if best_d < CHASE_RANGE2:
		wp = fleet_waypoint(best, WARP_HOME)
	else:
		if best == null and spare_computers:
			return direct_warship(w, fleet, own, enemies, false)
		var target: Planet = null
		if best != null:
			var owner := w.me()
			var half := Movement.fuel_capacity(fleet, owner, w.content) / 2
			if fleet.cargo[Fleet.CARGO_FUEL] < half and return_home(w, fleet, false):
				return 0
			var target_d := WARSHIP_START
			for p in w.state.planets:
				var taken := false
				for o in own:
					if o == fleet or o.waypoints.size() < 2:
						continue
					var next := o.waypoints[1]
					if next.target == "planet" and next.target_id == p.id:
						taken = true
						break
				if taken:
					continue
				var d := d2(p.x, p.y, best.x, best.y)
				if d < target_d:
					target = p
					target_d = d
			if target != null and target.id == fleet.planet:
				target = null
		if target == null:
			target = _nearest_enemy_planet(w, fleet)
		if target == null:
			wp = planet_waypoint(w, _unmarked_planet(w, fleet), WARP_HOME)
		else:
			wp = planet_waypoint(w, target.id, WARP_HOME)
	if (
		fleet.waypoints.size() > 1
		and fleet.waypoints[1].target == "planet"
		and wp.target == "planet"
	):
		return -1
	return 0 if go(w, fleet, wp) else -1


## The nearest planet of another player, unless the fleet is there; null otherwise.
static func _nearest_enemy_planet(w: ClassicWorld, fleet: Fleet) -> Planet:
	var best: Planet = null
	var best_d := WARSHIP_START
	for p in w.state.planets:
		if p.owner == -1 or p.owner == w.player:
			continue
		var d := d2(p.x, p.y, fleet.x, fleet.y)
		if d < best_d:
			best = p
			best_d = d
	if best != null and best.id == fleet.planet:
		return null
	return best


## The nearest planet planet_info byte 9 leaves unmarked, else one drawn.
static func _unmarked_planet(w: ClassicWorld, fleet: Fleet) -> int:
	var best := -1
	var best_d := WARSHIP_START
	for p in w.state.planets:
		if (w.planet_info[p.id] as PackedByteArray)[9] != 0:
			continue
		var d := d2(p.x, p.y, fleet.x, fleet.y)
		if d < best_d:
			best = p.id
			best_d = d
	if best == -1:
		best = w.state.planets[w.rng.random(w.state.planets.size())].id
	return best


# --- Colony targets ----------------------------------------------------------------------------


## `AI_RateColonyTargets`: the nearest planet free to settle, and for a fleet at one of the
## player's planets before WORMHOLE_TURN perhaps a wormhole instead (`pick_wormhole`). Planet_info
## byte 15 marks each planet: 0 free (Robotoids and Macinti: any unowned planet; others: unowned
## planets they could make habitable, else 8), 1 the player's, 2 another's, 4 claimed by another
## of the player's fleets heading there (Robotoids and Macinti: to colonize); the others mark the
## planets their turn file doesn't hold UNSEEN. Returns
## {planet: id or -1, wormhole: Wormhole or null}; with a wormhole the planet is -1. Without
## `wormholes` none is looked for (the original's call without a wormhole to fill in).
static func colony_target(w: ClassicWorld, fleet: Fleet, wormholes := true) -> Dictionary:
	var pid := w.personality_id()
	var plain := pid == ClassicWorld.ROBOTOIDS or pid == ClassicWorld.MACINTI
	if plain or not w.colony_targets_rated:
		for p in w.state.planets:
			var mark := 0
			if not plain and not w.loaded.has(p.id):
				mark = UNSEEN
			elif p.owner == -1:
				if not plain and terraformed_hab(w, p) < 0:
					mark = 8
			elif p.owner == w.player:
				mark = 1
			else:
				mark = 2
			info_set(w, p.id, 15, mark)
		for f in w.state.fleets:
			if f.owner != w.player or f == fleet or f.waypoints.size() < 2:
				continue
			var next := f.waypoints[1]
			if next.target == "planet" and (not plain or next.task == "colonize"):
				info_set(w, next.target_id, 15, 4)
	var best := -1
	var best_d := 99999999
	for p in w.state.planets:
		if (w.planet_info[p.id] as PackedByteArray)[15] != 0:
			continue
		var d := d2(fleet.x, fleet.y, p.x, p.y)
		if d < best_d:
			best = p.id
			best_d = d
	w.colony_targets_rated = true
	var hole: Wormhole = null
	if wormholes and fleet.planet != -1 and w.state.turn < WORMHOLE_TURN:
		if w.state.planet(fleet.planet).owner == w.player:
			hole = pick_wormhole(w, fleet.x, fleet.y, best_d)
	if hole != null:
		best = -1
	return {"planet": best, "wormhole": hole}


## A planet's habitability once the player terraforms it as far as it can toward its ideal
## (`Planet_HabValueTerraformed`).
static func terraformed_hab(w: ClassicWorld, p: Planet) -> int:
	var race := w.me().race
	var copy := p.copy() as Planet
	var t := Terraforming.targets(p, race, Terraforming.reach(w.me(), w.content), true)
	for i in 3:
		if t[0][i] != Terraforming.NONE:
			copy.environment[i] = t[0][i]
		if t[1][i] != Terraforming.NONE:
			copy.environment[i] = t[1][i]
	return PlanetEconomy.hab_value(copy, race)


static func info_set(w: ClassicWorld, planet_id: int, byte: int, value: int) -> void:
	var info: PackedByteArray = w.planet_info[planet_id]
	info[byte] = value
	w.planet_info[planet_id] = info


## `AI_PickWeighted`: a wormhole worth trying from (x, y), when the nearest free planet is
## `planet_d2` away: wormholes within twice that distance (the original squares the distance in 16
## bits, so a wormhole whose square wraps past 32767 is always in reach), scored 50 (unseen,
## farther than the planet), 90 (unseen, nearer) or 70 less 10 per percent of jump chance (seen);
## the best (the nearer of equals) is taken when a draw of 100 falls under its score.
static func pick_wormhole(w: ClassicWorld, x: int, y: int, planet_d2: int) -> Wormhole:
	var best: Wormhole = null
	var best_score := 0
	var best_d := 1000000
	for hole in w.state.wormholes:
		var dx := absi(x - hole.x)
		var dy := absi(y - hole.y)
		var d := (dx * dx + dy * dy) & 0xFFFF
		if d >= 0x8000:
			d -= 0x10000
		if d > planet_d2 * 4:
			continue
		var score: int
		if not hole.seen_by.has(w.player):
			score = 50 if planet_d2 < d else 90
		else:
			score = (7 - Wormholes.jump_chance(hole)) * 10
		if best_score < score or (best_score == score and d < best_d):
			best = hole
			best_score = score
			best_d = d
	if best != null and w.rng.random(100) < best_score:
		return best
	return null


# --- The other personalities' fleets -----------------------------------------------------------


## `AI_HasWarshipHull`: ships on a hull of WARSHIP (scout to dreadnought).
static func has_warship_hull(w: ClassicWorld, fleet: Fleet) -> bool:
	var owner := w.state.player(fleet.owner)
	for s in stacks_of(fleet):
		if hulls_of(w, WARSHIP).has(owner.ship_design(s.design).hull):
			return true
	return false


## `Fleet_HasArmedShips`: ships of an armed design (S16 `Design_IsArmed`).
static func is_armed(w: ClassicWorld, fleet: Fleet) -> bool:
	var owner := w.state.player(fleet.owner)
	for s in stacks_of(fleet):
		if BattleSetup.is_armed(owner.ship_design(s.design), w.content):
			return true
	return false


## `AI_AddWaypoint` appending: the waypoint follows the fleet's last one, or takes its place when
## it is there. False when refused.
static func go_after(w: ClassicWorld, fleet: Fleet, wp: Waypoint) -> bool:
	w.select_fleet(fleet)
	var last := fleet.waypoints.size() - 1
	var at := fleet.waypoints[last]
	var index := last + 1
	var type := "waypoint_add"
	if at.x == wp.x and at.y == wp.y:
		index = last
		type = "waypoint_change"
	var reason := w.order(
		{"type": type, "fleet": fleet.number, "index": index, "waypoint": wp.to_dict()}
	)
	return reason.is_empty()


## `AI_ScoreColonyTarget` (`spare_computers`) and `AI_ScoreColonyTarget2`: planet_info byte
## INFO_TARGET of `p` (0 for `from` itself, and with `spare_computers` for computer players'
## planets), more when near `from`; one marked HEADED counts only on a draw of 1 in 4.
static func target_score(w: ClassicWorld, from: Planet, p: Planet, spare_computers: bool) -> int:
	if p == from:
		return 0
	if spare_computers and p.owner >= 0 and w.is_computer(p.owner):
		return 0
	var worth: int = (w.planet_info[p.id] as PackedByteArray)[INFO_TARGET]
	if worth == 0:
		return 0
	var d := d2(from.x, from.y, p.x, p.y)
	if d < 2500:
		worth += 7
	elif d < 10000:
		worth += 5
	elif d < 22500:
		worth += 4
	elif d < 40000:
		worth += 3
	elif d < 90000:
		worth += 2
	elif d < 250000:
		worth += 1
	if worth & HEADED == 0 or w.rng.random(4) == 0:
		return worth
	return 0


## `AI_ChooseColonyTarget`: the nearest planet marked UNSEEN (rating the colony targets first
## when that wasn't done this turn, without wormholes); with `wormholes`, a fleet at a planet
## looks for a wormhole on a draw of WORMHOLE_PCT in 100 (`pick_wormhole`), which replaces the
## planet. Returns {planet: id or -1, wormhole: Wormhole or null}.
static func choose_colony_target(w: ClassicWorld, fleet: Fleet, wormholes: bool) -> Dictionary:
	if not w.colony_targets_rated:
		colony_target(w, fleet, false)
	var best := -1
	var best_d := 99999999
	for p in w.state.planets:
		if (w.planet_info[p.id] as PackedByteArray)[15] != UNSEEN:
			continue
		var d := d2(fleet.x, fleet.y, p.x, p.y)
		if d < best_d:
			best = p.id
			best_d = d
	var hole: Wormhole = null
	if wormholes and fleet.planet != -1 and w.rng.random(100) < WORMHOLE_PCT:
		hole = pick_wormhole(w, fleet.x, fleet.y, best_d)
	if hole != null:
		best = -1
	return {"planet": best, "wormhole": hole}


## `AI_DirectFleet` (Turindrones, Automitrons, Rototills): an armed fleet hunts the nearest of
## `enemies` (with `spare_computers` not computer players' fleets; one that `own` fleets already
## chase is passed over on a draw of 1 in 3) within CHASE_RANGE2; farther off, low on fuel (under
## half) it goes home, else to the planet nearest the prey that none of `own` heads for; with no
## prey at all and `spare_computers`, computer players' fleets count after all. Otherwise, and
## for an unarmed fleet, it explores (`choose_colony_target`), failing that goes to the planet
## `AI_ScoreColonyTarget2` rates best from the homeworld, else to any planet, drawn. A fleet
## already heading for a planet keeps going (-1); a planet chosen is marked claimed (planet_info
## byte 15 = 4); the orders go at the fleet's top warp, no easing (0, or -1 when refused).
static func direct_fleet(
	w: ClassicWorld,
	fleet: Fleet,
	own: Array[Fleet],
	enemies: Array[Fleet],
	spare_computers: bool,
	wormholes: bool
) -> int:
	var wp: Waypoint = null
	if is_armed(w, fleet):
		var best: Fleet = null
		var best_d := WARSHIP_START
		for e in enemies:
			if spare_computers and w.is_computer(e.owner):
				continue
			if _chased(own, fleet, e) and w.rng.random(3) == 0:
				continue
			var d := d2(e.x, e.y, fleet.x, fleet.y)
			if d < best_d:
				best = e
				best_d = d
		if best_d < CHASE_RANGE2:
			wp = fleet_waypoint(best, 0)
		elif best == null:
			if spare_computers:
				return direct_fleet(w, fleet, own, enemies, false, wormholes)
		else:
			var half := Movement.fuel_capacity(fleet, w.me(), w.content) / 2
			if fleet.cargo[Fleet.CARGO_FUEL] < half and return_home(w, fleet, false):
				return 0
			var target := _free_planet_near(w, fleet, own, best)
			if target != null and target.id != fleet.planet:
				wp = planet_waypoint(w, target.id, 0)
	if wp == null:
		wp = _exploring(w, fleet, wormholes)
	if (
		fleet.waypoints.size() > 1
		and fleet.waypoints[1].target == "planet"
		and wp.target == "planet"
	):
		return -1
	if wp.target == "planet":
		info_set(w, wp.target_id, 15, 4)
	wp.warp = Retargeting.default_warp(fleet, w.me(), w.content, false)
	return 0 if go(w, fleet, wp) else -1


## Whether one of `own` (not `fleet`) chases `prey` (its next waypoint targets it).
static func _chased(own: Array[Fleet], fleet: Fleet, prey: Fleet) -> bool:
	for o in own:
		if o == fleet or o.waypoints.size() < 2:
			continue
		var next := o.waypoints[1]
		if (
			next.target == "fleet"
			and next.target_owner == prey.owner
			and next.target_id == prey.number
		):
			return true
	return false


## `direct_fleet`'s waypoint for a fleet with no prey: a wormhole or a planet.
static func _exploring(w: ClassicWorld, fleet: Fleet, wormholes: bool) -> Waypoint:
	var pick := choose_colony_target(w, fleet, wormholes)
	var hole: Wormhole = pick["wormhole"]
	if hole != null:
		var wp := Waypoint.new(hole.x, hole.y)
		wp.target = "wormhole"
		wp.target_id = hole.number
		return wp
	var id: int = pick["planet"]
	if id == -1:
		var home := w.me().homeworld
		if home != -1:
			var from := w.state.planet(home)
			var rated := best_planet(
				w, home, func(p: Planet) -> int: return target_score(w, from, p, false)
			)
			if rated != null:
				id = rated.id
		if id == -1:
			id = w.state.planets[w.rng.random(w.state.planets.size())].id
	return planet_waypoint(w, id, 0)


## The loaded planet nearest `prey` that none of `own` (but `fleet`) heads for; null for none.
static func _free_planet_near(
	w: ClassicWorld, fleet: Fleet, own: Array[Fleet], prey: Fleet
) -> Planet:
	var target: Planet = null
	var target_d := WARSHIP_START
	for p in w.state.planets:
		if not w.loaded.has(p.id):
			continue
		var taken := false
		for o in own:
			if o == fleet or o.waypoints.size() < 2:
				continue
			var next := o.waypoints[1]
			if next.target == "planet" and next.target_id == p.id:
				taken = true
				break
		if taken:
			continue
		var d := d2(p.x, p.y, prey.x, prey.y)
		if d < target_d:
			target = p
			target_d = d
	return target
