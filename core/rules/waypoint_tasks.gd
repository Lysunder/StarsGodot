class_name WaypointTasks
extends RefCounted
## Waypoint tasks (spec S11): the four task passes, and resolving colonization (S17).
##
## Every task is built: transport, colonize, remote mining, merge, scrap (with Ultimate
## Recycling and the S24 tech bonus), lay mines, route and default orders (Routes), and transfer.
## Patrol acts with movement and battles.

## Ultimate Recycling banks at most this many resources per fleet and per planet (S11, fix B40).
const RECYCLING_MAX := 65535
const CARGO_COLONISTS := 3
const COLONIZER_TAG := "colonizer"
const MINERAL_RETURN := [3, 4]
## Minerals recovered by scrapping (S11 "Scrap"), by planet kind and Ultimate Recycling.
const SCRAP_RETURN := {
	"starbase": [4, 5],
	"starbase_recycling": [9, 10],
	"planet": [1, 3],
	"planet_recycling": [9, 20],
}
const TRANSFERRED_COST_DIVISOR := 4
const DESIGN_SLOTS := 16
const MINING_RATE_MAX := 4000
## Fill and wait percentages use the capacity capped here; from 65,536 on they divide first.
## A fleet as the "where" of a transport message: this plus the fleet's parameter value (S21).
const FLEET_OBJECT := 32768
## The first half of a transport message's "where" for a packet or salvage pile (65534, S21).
const SPACE_OBJECT := 65534
## Transport actions that load (S21 "load refused").
const LOAD_ACTIONS := ["load_all", "load", "fill_percent", "wait_percent"]
const PERCENT_CAPACITY_MAX := 2000000
const PERCENT_SPLIT := 65536

var _state: GameState
var _content: ContentRegistry
var _rng: StarsRandom
## The unowned planet whose own remote miner is the transport partner, during one transport.
var _site: Planet = null
## The packet or salvage pile the current transport works with (S14 "Transport with salvage and
## packets"), else null.
var _pile: Packet = null
## The task pass being run (1..4).
var _pass := 0
## Colonists landed, waiting for the next ground combat (S11 "Colonize", S17).
var _combat: GroundCombat


func _init(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	_state = state
	_content = content
	_rng = rng
	_combat = GroundCombat.new(state, content, rng)


## Pass 1 and 3 unload, pass 2 and 4 load (S11 "Passes"), at each fleet's current waypoint.
func run_pass(pass_number: int) -> void:
	_pass = pass_number
	var loading := pass_number % 2 == 0
	var fleets: Array[Fleet] = _state.fleets.duplicate()
	for fleet in fleets:
		if fleet.ship_count() == 0 or fleet.waypoints.is_empty():
			continue
		var wp := fleet.waypoints[0]
		match wp.task:
			"transport":
				_transport(fleet, wp, loading)
			"colonize":
				_colonize(fleet, wp)
			"merge":
				if loading:
					_merge(fleet, wp)
			"scrap":
				if pass_number == 1:
					_scrap(fleet)
			"transfer":
				if pass_number == 4:
					_transfer(fleet, wp)
			"remote_mine":
				if pass_number == 3:
					_remote_mine(fleet, wp)
			"lay_mines":
				if pass_number == 3:
					_lay_mines(fleet, wp)
			"none":
				# a Space Demolition fleet lays mines on its way to a lay-mines waypoint
				if pass_number == 3 and fleet.waypoints.size() > 1:
					if fleet.waypoints[1].task == "lay_mines" and _lays_while_moving(fleet):
						Minefields.lay(_state, _content, fleet, fleet.waypoints[1], true)
			"route":
				_route(fleet, wp)
			"patrol":
				pass
			_:
				push_warning("waypoint task %s is not implemented yet" % wp.task)


## S11 "Transport": the other side is the target fleet, the planet the fleet is at, a packet or
## salvage pile (S14), or deep space. Unload actions run in passes 1 and 3 and are cleared once
## done; loads run in passes 2 and 4 and end the task. A refused colonist unload cancels the task.
func _transport(fleet: Fleet, wp: Waypoint, loading: bool) -> void:
	var other: Fleet = null
	var planet: Planet = null
	_pile = null
	match wp.target:
		"fleet":
			other = _state.fleet(wp.target_owner, wp.target_id)
			if other == null or other == fleet or other.x != fleet.x or other.y != fleet.y:
				other = null
				if loading:
					_task_done(fleet, wp)
				return
		"planet":
			planet = _state.planet(fleet.planet) if fleet.planet >= 0 else null
			if planet != null and planet.owner < 0:
				var miner := _resting_miner(fleet, planet)
				if miner != null:
					other = miner
					_site = planet
					planet = null
		"packet":
			_pile = _find_packet(wp.target_owner, wp.target_id)
			if _pile == null:
				if loading:
					_task_done(fleet, wp)
				return
		"none":
			pass
		_:
			# minefields, wormholes and the Mystery Trader carry no cargo
			_refuse(fleet, wp, "fleet.transport_futile", [_fleet_word(fleet)])
			return
	var cargo: Array = wp.task_data.get("cargo", [])
	var done := true
	var wait_for_space := false
	var dunnage := false
	var fuel_optimal := false
	for c in mini(cargo.size(), Fleet.CARGO_FUEL + 1):
		if c == Fleet.CARGO_FUEL and planet != null:
			continue
		if _pile != null and c >= CARGO_COLONISTS:
			continue
		var action: String = cargo[c].get("action", "none")
		var amount: int = cargo[c].get("amount", 0)
		var have := fleet.cargo[c]
		var unload := -1
		if loading and action in LOAD_ACTIONS and _refused_load(fleet, other, planet, c):
			_task_done(fleet, wp)
			_site = null
			return
		match action:
			"load_all", "load":
				if loading:
					_load(fleet, other, planet, c, -1 if action == "load_all" else amount)
			"unload_all", "unload":
				if not loading:
					unload = have if action == "unload_all" else mini(amount, have)
			"fill_percent", "wait_percent":
				if loading and _can_load(fleet, other, planet, c):
					var x := mini(_percent_of_capacity(fleet, c, amount), _free_space(fleet, c))
					if x == 0:
						if action == "wait_percent":
							if c == Fleet.CARGO_FUEL:
								done = false
							else:
								wait_for_space = true
					elif _load(fleet, other, planet, c, x) != x:
						done = false
			"set_amount":
				var diff := amount - have
				if diff < 0 and not loading:
					unload = -diff
				elif diff >= 0 and loading and _can_load(fleet, other, planet, c):
					if _available(other, planet, c) < diff:
						done = false
						if _pass == 4:
							_set_short(fleet, other, planet, c, amount)
					_load(fleet, other, planet, c, diff)
			"set_waypoint":
				var diff := _available(other, planet, c) - amount
				if diff < 0 and not loading:
					unload = mini(-diff, have)
				elif diff > 0 and loading:
					_load(fleet, other, planet, c, diff)
			"load_optimal":
				if c == Fleet.CARGO_FUEL:
					fuel_optimal = true
				elif loading:
					dunnage = true
			"none":
				pass
			_:
				push_warning("transport action %s is not implemented yet" % action)
		if unload >= 0:
			if not _unload(fleet, other, planet, c, unload):
				_task_done(fleet, wp)
				return
			cargo[c] = {"action": "none", "amount": 0}
	if loading and fuel_optimal and not dunnage:
		done = _fuel_optimal(fleet, other, planet) and done
	if loading and dunnage and done:
		var space := _cargo_space(fleet, _state.player(fleet.owner))
		if space > 0 or fuel_optimal:
			for c in mini(cargo.size(), Fleet.CARGO_FUEL):
				if cargo[c].get("action", "none") == "load_optimal":
					_load(fleet, other, planet, c, -1)
			if fuel_optimal:
				done = _fuel_optimal(fleet, other, planet) and done
	if wait_for_space and _cargo_space(fleet, _state.player(fleet.owner)) > 0:
		done = false
	_site = null
	_pile = null
	if loading and done:
		_task_done(fleet, wp)


## The packet or salvage pile with this owner and number, or null.
func _find_packet(owner: int, number: int) -> Packet:
	for p in _state.packets:
		if p.owner == owner and p.number == number:
			return p
	return null


## S21: in the last load pass a load action from a planet the player doesn't own, from another
## player's fleet or from deep space sends its refusal and cancels the transport task (fuel is
## never loaded from planets).
func _refused_load(fleet: Fleet, other: Fleet, planet: Planet, c: int) -> bool:
	if _pass != 4 or _pile != null or _site != null:
		return false
	if can_steal(_state, _content, fleet, other, planet, c):
		return false
	var type := ""
	if planet != null:
		if planet.owner == fleet.owner or c == Fleet.CARGO_FUEL:
			return false
		type = "fleet.load_refused"
	elif other != null:
		if other.owner == fleet.owner:
			return false
		type = "fleet.load_foreign_fleet"
	else:
		type = "fleet.load_deep_space"
	_fleet_message(fleet, type, [_fleet_word(fleet), c])
	return true


## A fleet as a message parameter (S21 `fleet`): owner × 512 + number.
static func _fleet_word(fleet: Fleet) -> int:
	return fleet.owner * 512 + fleet.number


## Sends `message.<type>` to the fleet's owner, goto the fleet.
func _fleet_message(fleet: Fleet, type: String, params: Array) -> void:
	TurnMessages.add(
		_state,
		_content,
		fleet.owner,
		"message." + type,
		{"fleet": fleet.number, "owner": fleet.owner},
		params
	)


## The "where" of a transport message (S21 `object_kind`, `object`): [-1, planet id],
## [-1, 32768 + the fleet's parameter value] or [65534, the packet's `space_object` value].
func _where(other: Fleet, planet: Planet) -> Array:
	if _pile != null:
		return [SPACE_OBJECT, Packets.object_word(_pile)]
	if other != null:
		return [-1, FLEET_OBJECT + _fleet_word(other)]
	return [-1, planet.id if planet != null else -1]


## A load message: "loaded" for minerals and fuel, "beamed up" for colonists.
func _load_message(fleet: Fleet, c: int, moved: int, where: Array) -> void:
	var type := "fleet.beamed_up" if c == CARGO_COLONISTS else "fleet.loaded"
	_fleet_message(fleet, type, [_fleet_word(fleet), moved, c] + where)


## An unload message: "unloaded" for minerals and fuel, "beamed down" for colonists.
func _unload_message(fleet: Fleet, c: int, moved: int, where: Array) -> void:
	var type := "fleet.beamed_down" if c == CARGO_COLONISTS else "fleet.unloaded"
	_fleet_message(fleet, type, [_fleet_word(fleet), moved, c] + where)


## The fleet owner's first remote miner resting at this unowned planet (didn't move, mining rate
## above 0): transport there goes through it (S11 "Transport at a mining site").
func _resting_miner(fleet: Fleet, planet: Planet) -> Fleet:
	var owner := _state.player(fleet.owner)
	for f in _state.fleets:
		if f == fleet or f.owner != fleet.owner or f.planet != planet.id or not f.did_not_move:
			continue
		if mining_rate(f, owner, _content) > 0:
			return f
	return null


## "Load optimal" fuel (S11): with no next waypoint, all fuel goes to the other side; otherwise
## fuel beyond what the next leg needs goes to it, or the fleet waits when short (returns false).
func _fuel_optimal(fleet: Fleet, other: Fleet, planet: Planet) -> bool:
	var owner := _state.player(fleet.owner)
	var give := fleet.cargo[Fleet.CARGO_FUEL]
	if fleet.waypoints.size() >= 2:
		var next := fleet.waypoints[1]
		var dx := next.x - fleet.x
		var dy := next.y - fleet.y
		var distance := int(sqrt(float(dx * dx + dy * dy)) + Movement.DISTANCE_ROUND_UP)
		var need := Movement.fuel_needed(fleet, owner, next.warp, distance, _content)
		if fleet.cargo[Fleet.CARGO_FUEL] < need:
			_short_of_fuel(fleet, other, planet, need)
			return false
		give -= need
	if other == null or give <= 0:
		return true
	var moved := mini(give, _free_space(other, Fleet.CARGO_FUEL))
	fleet.cargo[Fleet.CARGO_FUEL] -= moved
	other.cargo[Fleet.CARGO_FUEL] += moved
	if moved > 0:
		_unload_message(fleet, Fleet.CARGO_FUEL, moved, _where(other, null))
	return true


## S21: load optimal can't fuel the trip to the next waypoint: in the last load pass, with nowhere
## to load fuel from, "failed to load fuel"; in the first load pass, waiting for fuel, or the trip
## needs more than the tanks hold.
func _short_of_fuel(fleet: Fleet, other: Fleet, planet: Planet, need: int) -> void:
	var word := _fleet_word(fleet)
	var where := _where(other, planet)
	if _pass == 4 and not _can_load(fleet, other, planet, Fleet.CARGO_FUEL):
		_fleet_message(fleet, "fleet.fuel_load_failed", [word] + where)
	elif _pass == 2:
		var capacity := Movement.fuel_capacity(fleet, _state.player(fleet.owner), _content)
		if need <= capacity:
			var short := need - fleet.cargo[Fleet.CARGO_FUEL]
			_fleet_message(fleet, "fleet.fuel_waiting", where + [word, short])
		else:
			_fleet_message(fleet, "fleet.fuel_out_of_reach", [word, capacity, need])


## S21: a "set amount" the other side can't fill, in the last load pass.
func _set_short(fleet: Fleet, other: Fleet, planet: Planet, c: int, amount: int) -> void:
	var kind := "fleet.set_short_colonists" if c == CARGO_COLONISTS else "fleet.set_short"
	_fleet_message(fleet, kind, [_fleet_word(fleet), c, amount] + _where(other, planet))


## What the other side has of cargo type `c`: the target fleet's cargo or the planet's surface or
## population; 0 in deep space.
func _available(other: Fleet, planet: Planet, c: int) -> int:
	if _pile != null:
		return _pile.minerals[c] if c < CARGO_COLONISTS else 0
	if _site != null and c != Fleet.CARGO_FUEL:
		return _site.population if c == CARGO_COLONISTS else _site.surface[c]
	if other != null:
		return other.cargo[c]
	if planet == null or c == Fleet.CARGO_FUEL:
		return 0
	return planet.population if c == CARGO_COLONISTS else planet.surface[c]


## Loads come only from the fleet owner's own planet (not fuel) or own fleets (fix B26/B15), or
## from anyone's packet or salvage (minerals only, S14).
func _can_load(fleet: Fleet, other: Fleet, planet: Planet, c: int) -> bool:
	if _pile != null:
		return c < CARGO_COLONISTS
	if other != null:
		return other.owner == fleet.owner or can_steal(_state, _content, fleet, other, null, c)
	if planet == null:
		return false
	if planet.owner == fleet.owner:
		return c != Fleet.CARGO_FUEL
	return can_steal(_state, _content, fleet, null, planet, c)


## S11 "Stealing" (fix B41): a fleet with a cargo-stealing scanner (tag `steals_from_fleets`)
## takes any cargo from another player's fleet; one with a mineral-stealing scanner (tag
## `steals_from_planets`) takes minerals from another player's planet.
static func can_steal(
	state: GameState, content: ContentRegistry, fleet: Fleet, other: Fleet, planet: Planet, c: int
) -> bool:
	var scanner := Scanning.fleet_scanner(fleet, state.player(fleet.owner), content)
	if other != null:
		return other.owner != fleet.owner and scanner.cargo
	return (
		planet != null
		and planet.owner >= 0
		and planet.owner != fleet.owner
		and c < CARGO_COLONISTS
		and scanner.minerals
	)


## n percent of the fleet's capacity for cargo type `c` (fuel capacity for fuel), the capacity
## capped at 2,000,000 (S11 "Fill up to n%").
func _percent_of_capacity(fleet: Fleet, c: int, n: int) -> int:
	var owner := _state.player(fleet.owner)
	var cap := 0
	if c == Fleet.CARGO_FUEL:
		cap = Movement.fuel_capacity(fleet, owner, _content)
	else:
		for stack in fleet.stacks:
			cap += stack.count * PartRules.cargo_capacity(owner.ship_design(stack.design), _content)
	cap = mini(cap, PERCENT_CAPACITY_MAX)
	if cap < PERCENT_SPLIT:
		return n * cap / 100
	return n * (cap / 100)


## Takes up to `want` (-1: all there is) of cargo type `c` from the fleet owner's own planet or
## fleet, limited by the fleet's free space; returns what moved. Anything else is skipped (fix
## B26/B15).
func _load(fleet: Fleet, other: Fleet, planet: Planet, c: int, want: int) -> int:
	if not _can_load(fleet, other, planet, c):
		return 0
	var moved := mini(_available(other, planet, c), _free_space(fleet, c))
	if want >= 0:
		moved = mini(moved, want)
	if moved <= 0:
		return 0
	if _site != null and c != Fleet.CARGO_FUEL:
		# from the miner's hold first, the rest from the planet's surface
		var asked := mini(want if want >= 0 else moved, _free_space(fleet, c))
		var from_miner := mini(moved, other.cargo[c])
		other.cargo[c] -= from_miner
		var there := _site.population if c == CARGO_COLONISTS else _site.surface[c]
		var from_site := mini(asked - from_miner, there)
		if c == CARGO_COLONISTS:
			_site.population -= from_site
		else:
			_site.surface[c] -= from_site
		fleet.cargo[c] += from_miner + from_site
		if from_miner > 0:
			_load_message(fleet, c, from_miner, _where(other, null))
		if from_site > 0:
			_fleet_message(
				fleet,
				"fleet.miner_loaded",
				[_fleet_word(fleet), from_site, c, _fleet_word(other), _site.id]
			)
		return from_miner + from_site
	fleet.cargo[c] += moved
	if _pile != null:
		_pile.minerals[c] -= moved
	elif other != null:
		other.cargo[c] -= moved
	elif c == CARGO_COLONISTS:
		planet.population -= moved
	else:
		planet.surface[c] -= moved
	if other != null and other.owner != fleet.owner:
		_fleet_message(fleet, "fleet.stole", [_fleet_word(fleet), moved, c, _fleet_word(other)])
	else:
		_load_message(fleet, c, moved, _where(other, planet))
	return moved


## Gives up to `amount` of cargo type `c` to the other side (S11 "Unloading"). Returns false when a
## colonist unload is refused, which cancels the task.
func _unload(fleet: Fleet, other: Fleet, planet: Planet, c: int, amount: int) -> bool:
	if _pile != null:
		# only the rounding room of the pile's recorded mass takes more (S14)
		var moved := mini(amount, maxi(Packets.slack(_pile), 0))
		if c < CARGO_COLONISTS and moved > 0:
			fleet.cargo[c] -= moved
			_pile.minerals[c] += moved
			_unload_message(fleet, c, moved, _where(null, null))
		return true
	if other != null:
		var foreign := other.owner != fleet.owner
		if foreign and c == CARGO_COLONISTS:
			_fleet_message(fleet, "fleet.colonists_to_foreign_fleet", [_fleet_word(fleet)])
			return false
		if foreign and c != Fleet.CARGO_FUEL:
			return true
		if foreign and _state.player(other.owner).relations[fleet.owner] == "enemy":
			return true
		var moved := mini(amount, _free_space(other, c))
		if moved > 0:
			fleet.cargo[c] -= moved
			other.cargo[c] += moved
			_unload_message(fleet, c, moved, _where(other, null))
		return true
	if planet == null:
		if c == CARGO_COLONISTS:
			_fleet_message(fleet, "fleet.colonists_to_deep_space", [_fleet_word(fleet)])
			return false
		# minerals unloaded in deep space are lost (S14); fuel stays aboard
		if c != Fleet.CARGO_FUEL and amount > 0:
			fleet.cargo[c] -= amount
			_unload_message(fleet, c, amount, [fleet.x, fleet.y])
		return true
	if c == Fleet.CARGO_FUEL or amount <= 0:
		return true
	if c != CARGO_COLONISTS:
		fleet.cargo[c] -= amount
		planet.surface[c] += amount
		_unload_message(fleet, c, amount, _where(null, planet))
		return true
	if planet.owner == fleet.owner:
		fleet.cargo[c] -= amount
		planet.population += amount
		_unload_message(fleet, c, amount, _where(null, planet))
		return true
	var race := _state.player(fleet.owner).race
	var refusal := ""
	if planet.owner < 0:
		refusal = "fleet.colonists_to_empty_planet"
	elif RaceMath.trait_param(race, _content, "transport.no_invasion", 0):
		refusal = "fleet.colonists_overruled"
	elif planet.starbase != null:
		refusal = "fleet.colonists_starbase"
	if not refusal.is_empty():
		_fleet_message(fleet, refusal, [_fleet_word(fleet), planet.id])
		return false
	_record(fleet, planet, amount)
	fleet.cargo[c] -= amount
	return true


## Free cargo space for minerals and colonists, free fuel space for fuel.
func _free_space(fleet: Fleet, c: int) -> int:
	var owner := _state.player(fleet.owner)
	if c == Fleet.CARGO_FUEL:
		return maxi(Movement.fuel_capacity(fleet, owner, _content) - fleet.cargo[c], 0)
	return _cargo_space(fleet, owner)


func _cargo_space(fleet: Fleet, owner: Player) -> int:
	var capacity := 0
	for stack in fleet.stacks:
		var design := owner.ship_design(stack.design)
		if design != null:
			capacity += stack.count * PartRules.cargo_capacity(design, _content)
	var used := 0
	for c in Fleet.CARGO_FUEL:
		used += fleet.cargo[c]
	return maxi(capacity - used, 0)


## S11 "Colonize": the fleet is taken apart over an empty planet; its colonists are recorded for
## the next resolution.
func _colonize(fleet: Fleet, wp: Waypoint) -> void:
	var word := _fleet_word(fleet)
	if fleet.planet < 0:
		_refuse(fleet, wp, "fleet.colonize_not_at_planet", [word])
		return
	var planet := _state.planet(fleet.planet)
	if planet.owner != -1:
		_refuse(fleet, wp, "fleet.colonize_populated", [word, planet.id, planet.id])
		return
	if fleet.cargo[CARGO_COLONISTS] == 0:
		_refuse(fleet, wp, "fleet.colonize_no_colonists", [word, planet.id])
		return
	var owner := _state.player(fleet.owner)
	var colonizer := false
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		for slot in owner.ship_design(stack.design).parts:
			if not slot.part.is_empty() and slot.count > 0:
				if (_content.part(slot.part).get("tags", []) as Array).has(COLONIZER_TAG):
					colonizer = true
	if not colonizer:
		_refuse(fleet, wp, "fleet.colonize_no_module", [word, planet.id, word])
		return
	var value := _ships_value(fleet, owner)
	var deposited := 0
	for m in 3:
		var amount := value[m] * MINERAL_RETURN[0] / MINERAL_RETURN[1] + fleet.cargo[m]
		planet.surface[m] += amount
		deposited += amount
	_record(fleet, planet, fleet.cargo[CARGO_COLONISTS])
	_scrap_messages(fleet, planet, deposited)
	_dismantle(fleet)


## The minerals the fleet's ships are worth when taken apart: per stack, ships x the design's
## cost, a quarter for transferred designs, and never more than what was paid (fix B14) when that
## is recorded.
func _ships_value(fleet: Fleet, owner: Player) -> Array[int]:
	var value: Array[int] = [0, 0, 0, 0]
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		var design := owner.ship_design(stack.design)
		# without the new-tech double price, which the original turns off while scrapping; at the
		# design's stored stats (the tech levels the turn started with) unless Bleeding Edge
		# prices it again at current tech
		var levels: Array[int] = []
		var start: Variant = _state.turn_start_tech.get(owner.index)
		var bleeding := (
			RaceMath.trait_param(owner.race, _content, "production.cost_at_tech_level_pct", 100)
			!= 100
		)
		if start != null and not bleeding:
			levels.assign(start)
		var each := ProductionCosts.design_cost(design, owner, _content, true, levels)
		var recorded := stack.paid.any(func(v: int) -> bool: return v != 0)
		for m in value.size():
			var v := stack.count * each[m]
			if design.transferred:
				v /= TRANSFERRED_COST_DIVISOR
			if recorded:
				v = mini(v, stack.paid[m])
			value[m] += v
	return value


## S21: a fleet taken apart at a planet: "dismantled for n kT" to its owner (described by its main
## design; the starbase form when the planet has a starbase), then "has been dismantled" to the
## planet's owner (none for an unowned planet).
## The scrap messages; `gained` is the planet owner's tech bonus try (S24, at a starbase): a field
## + 1 or -(Mystery Trader bit + 1) changes that owner's message.
func _scrap_messages(
	fleet: Fleet, planet: Planet, deposited: int, gained := 0, recycled := -1
) -> void:
	var at_starbase := planet.starbase != null
	var goto := {"planet": planet.id}
	var described := FleetOrders.designs_word(fleet, _state.player(fleet.owner), _content)
	var type := "scrapped_starbase" if at_starbase else "scrapped"
	var params := [described, deposited, planet.id]
	var extra := []
	if recycled >= 0:
		type += "_recycled"
		extra = [recycled]
	TurnMessages.add(_state, _content, fleet.owner, "message.fleet." + type, goto, params + extra)
	if planet.owner < 0:
		return
	var said := [_fleet_word(fleet), deposited, planet.id] + extra
	if gained > 0:
		TurnMessages.add(
			_state,
			_content,
			planet.owner,
			"message.planet.ships_scrapped_level" + ("_recycled" if recycled >= 0 else ""),
			{"research": true},
			said + ([gained - 1] if recycled >= 0 else [gained - 1, 0])
		)
	elif gained < 0:
		var item := MysteryTrader.item_of(_content, -gained - 1)
		TurnMessages.add(
			_state,
			_content,
			planet.owner,
			"message.planet.ships_scrapped_part" + ("_recycled" if recycled >= 0 else ""),
			{"item": item},
			said + [-gained - 1]
		)
	else:
		type = "ships_scrapped_starbase" if at_starbase else "ships_scrapped"
		if recycled >= 0:
			type += "_recycled"
		TurnMessages.add(_state, _content, planet.owner, "message.planet." + type, goto, said)


## The fleet's ships are gone: their designs' existing counts drop and the fleet is deleted.
func _dismantle(fleet: Fleet) -> void:
	var owner := _state.player(fleet.owner)
	for stack in fleet.stacks:
		owner.ship_design(stack.design).remaining -= stack.count
	FleetOrders.delete_fleet(_state, fleet, -1, true)


## S11 "Merge with fleet": the fleet's ships join the target fleet of waypoint 0, which must be the
## same player's, have ships and be at the same place; cargo, fuel and damage follow the ships.
func _merge(fleet: Fleet, wp: Waypoint) -> void:
	var target: Fleet = null
	if wp.target == "fleet":
		target = _state.fleet(wp.target_owner, wp.target_id)
	if target == null or target.ship_count() == 0:
		_refuse(fleet, wp, "fleet.merge_no_target", [_fleet_word(fleet)])
		return
	if target == fleet:
		_task_done(fleet, wp)
		return
	if target.owner != fleet.owner:
		_refuse(fleet, wp, "fleet.merge_not_yours", [_fleet_word(fleet)])
		return
	var ships := {}
	for stack in fleet.stacks:
		ships[stack.design] = stack.count
	var described := FleetOrders.designs_word(fleet, _state.player(fleet.owner), _content)
	TurnMessages.add(
		_state,
		_content,
		target.owner,
		"message.fleet.merged",
		{"fleet": target.number, "owner": target.owner},
		[described, _fleet_word(target)]
	)
	FleetOrders.move_ships(_state, _content, target, fleet, ships, -1)


## S11 "Route": an idle fleet at its owner's planet with a route follows it; in pass 4 an idle
## fleet at another planet gets default orders (a merge they give is done at once).
func _route(fleet: Fleet, wp: Waypoint) -> void:
	if fleet.waypoints.size() != 1 or fleet.planet < 0:
		return
	var planet := _state.planet(fleet.planet)
	if planet.owner == fleet.owner and planet.route >= 0:
		var warp := Routes.follow(_state, _content, fleet, planet)
		_fleet_message(
			fleet,
			"fleet.rerouted" if warp != 0 else "fleet.reroute_no_fuel",
			[_fleet_word(fleet), planet.id, planet.route]
		)
	elif _pass == 4 and Routes.default_orders(_state, _content, fleet, planet) != null:
		_merge(fleet, wp)


## S11 "Remote mining" (pass 3, fleets that didn't move): an unowned planet is mined at the
## fleet's mining rate; the task stays. In deep space, at another player's planet (unless the race
## lives in space) or without mining robots the task is cleared.
## S11 "Lay mines": a fleet that moved this turn lays only if its race lays while moving (half).
func _lay_mines(fleet: Fleet, wp: Waypoint) -> void:
	var moved := not fleet.did_not_move
	if moved and not _lays_while_moving(fleet):
		return
	Minefields.lay(_state, _content, fleet, wp, moved)


func _lays_while_moving(fleet: Fleet) -> bool:
	var race := _state.player(fleet.owner).race
	return RaceMath.trait_param(race, _content, "minefield.lay_while_moving", 0) != 0


func _remote_mine(fleet: Fleet, wp: Waypoint) -> void:
	if not fleet.did_not_move:
		return
	var word := _fleet_word(fleet)
	if fleet.planet < 0:
		_refuse(fleet, wp, "fleet.remote_mine_deep_space", [word])
		return
	var planet := _state.planet(fleet.planet)
	var rate := mining_rate(fleet, _state.player(fleet.owner), _content)
	if rate <= 0:
		_refuse(fleet, wp, "fleet.remote_mine_no_robots", [word, planet.id])
		return
	if planet.owner >= 0:
		var race := _state.player(fleet.owner).race
		if not RaceMath.trait_param(race, _content, "transport.no_invasion", 0):
			_refuse(fleet, wp, "fleet.remote_mine_inhabited", [word, planet.id])
		return
	PlanetEconomy.mine_remote(planet, rate, _rng)


## The fleet's mining rate: ships × the design's mining robots' `mining_rate`, at most 4,000.
static func mining_rate(fleet: Fleet, owner: Player, content: ContentRegistry) -> int:
	var rate := 0
	for stack in fleet.stacks:
		var design := owner.ship_design(stack.design)
		for slot in design.parts:
			if not slot.part.is_empty() and slot.count > 0:
				rate += (
					stack.count
					* slot.count
					* int(content.part(slot.part).get("stats", {}).get("mining_rate", 0))
				)
	return mini(rate, MINING_RATE_MAX)


## S11 "Scrap": the fleet is taken apart at a planet; the planet gets part of the ships' minerals
## and all minerals in the cargo, and the colonists if it is the fleet owner's.
func _scrap(fleet: Fleet) -> void:
	var owner := _state.player(fleet.owner)
	if fleet.planet < 0:
		_scrap_in_space(fleet, owner)
		return
	var planet := _state.planet(fleet.planet)
	var recycling := (
		planet.owner >= 0
		and RaceMath.trait_param(_state.player(planet.owner).race, _content, "scrap.recycling", 0)
	)
	var kind := "starbase" if planet.starbase != null else "planet"
	var ratio: Array = SCRAP_RETURN[kind + ("_recycling" if recycling else "")]
	var value := _ships_value(fleet, owner)
	var deposited := 0
	for m in 3:
		var amount: int = value[m] * ratio[0] / ratio[1] + fleet.cargo[m]
		planet.surface[m] += amount
		deposited += amount
	if planet.owner == fleet.owner:
		planet.population += fleet.cargo[CARGO_COLONISTS]
	var recycled := -1
	if recycling:
		recycled = _recycle(planet, mini(value[3], RECYCLING_MAX))
	var gained := 0
	if planet.starbase != null and planet.owner >= 0:
		gained = TechGain.try_bonus(
			_state.player(planet.owner),
			TechGain.tech_needed(fleet, owner, _content),
			_content,
			_rng
		)
	_scrap_messages(fleet, planet, deposited, gained, recycled)
	_dismantle(fleet)


## S11 "Ultimate Recycling resources": banks `r` resources at the planet for this turn's
## production (at most RECYCLING_MAX, fix B40) and returns what the messages report.
func _recycle(planet: Planet, r: int) -> int:
	_state.recycled[planet.id] = mini(_state.recycled.get(planet.id, 0) + r, RECYCLING_MAX)
	if r <= 0:
		return 0
	var have := PlanetEconomy.resources(planet, _state.player(planet.owner).race, _content)
	return r * have / (r + have)


## S11 "Scrap" in deep space (S14 "Salvage"): a third of the ships' minerals and the cargo's
## minerals are left as a new salvage pile; colonists are lost.
func _scrap_in_space(fleet: Fleet, owner: Player) -> void:
	var ratio: Array = SCRAP_RETURN["planet"]
	var value := _ships_value(fleet, owner)
	var minerals: Array[int] = [0, 0, 0]
	for m in 3:
		minerals[m] = value[m] * ratio[0] / ratio[1] + fleet.cargo[m]
	var described := FleetOrders.designs_word(fleet, owner, _content)
	var pile := Packets.drop_salvage(
		_state, _content, _rng, fleet.owner, fleet.x, fleet.y, minerals
	)
	if pile != null:
		TurnMessages.add(
			_state,
			_content,
			fleet.owner,
			"message.fleet.scrapped_in_space",
			Packets.goto_of(pile),
			[Packets.object_word(pile), described]
		)
	_dismantle(fleet)


## S11 "Transfer fleet": the fleet becomes a new fleet of the receiving player (task data word 0,
## counting players without the giver). Each design maps to an identical transferred design of the
## receiver, else to the receiver's next free slot as a transferred copy.
func _transfer(fleet: Fleet, wp: Waypoint) -> void:
	var words: Array = wp.task_data.get("raw", [])
	var to: int = words[0] if not words.is_empty() else 0
	if to >= fleet.owner:
		to += 1
	var word := _fleet_word(fleet)
	if to < 0 or to >= _state.players.size() or _state.player(to).eliminated:
		_refuse(fleet, wp, "fleet.give_dead", [word])
		return
	var receiver := _state.player(to)
	if not receiver.is_human() or not receiver.active or receiver.relations[fleet.owner] == "enemy":
		_refuse(fleet, wp, "fleet.give_refused", [to])
		return
	if fleet.cargo[CARGO_COLONISTS] > 0:
		_refuse(fleet, wp, "fleet.give_colonists", [word])
		return
	var giver := _state.player(fleet.owner)
	var slots := {}
	var free := -1
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		var slot := _identical_transferred(receiver, giver.ship_design(stack.design))
		if slot < 0:
			free += 1
			while free < DESIGN_SLOTS and receiver.ship_design(free) != null:
				free += 1
			if free >= DESIGN_SLOTS:
				_no_room_to_give(fleet, wp, to)
				return
			slot = free
		slots[stack.design] = slot
	var created := _state.add_fleet(to, _content.constant("constant.limits.fleets_per_player"))
	if created == null:
		_no_room_to_give(fleet, wp, to)
		return
	created.x = fleet.x
	created.y = fleet.y
	created.planet = fleet.planet
	var here := Waypoint.new(fleet.x, fleet.y)
	if fleet.planet >= 0:
		here.target = "planet"
		here.target_id = fleet.planet
	created.waypoints.append(here)
	created.cargo = fleet.cargo.duplicate()
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		var slot: int = slots[stack.design]
		var design := receiver.ship_design(slot)
		if design == null:
			design = giver.ship_design(stack.design).copy() as Design
			design.slot = slot
			design.transferred = true
			design.built = 0
			design.remaining = 0
			receiver.set_design(design, false)
		var moved := created.add_ships(slot, stack.count)
		moved.damaged_percent = stack.damaged_percent
		moved.damage = stack.damage
		moved.paid = stack.paid.duplicate()
		design.built += stack.count
		design.remaining += stack.count
	var goto := {"fleet": created.number, "owner": to}
	var given := FleetOrders.designs_word(fleet, giver, _content)
	var got := FleetOrders.designs_word(created, receiver, _content)
	TurnMessages.add(_state, _content, fleet.owner, "message.fleet.given", goto, [given, to])
	TurnMessages.add(_state, _content, to, "message.fleet.received", goto, [fleet.owner, got])
	_dismantle(fleet)


## The receiver has no free design slot or fleet number: both players are told; the task ends.
func _no_room_to_give(fleet: Fleet, wp: Waypoint, to: int) -> void:
	_fleet_message(fleet, "fleet.give_no_room", [_fleet_word(fleet), to])
	TurnMessages.add(_state, _content, to, "message.fleet.receive_no_room", {}, [fleet.owner])
	_task_done(fleet, wp)


## A task that cannot be done: its message (goto the fleet), then the task ends (S21 "Fleet tasks").
func _refuse(fleet: Fleet, wp: Waypoint, type: String, params: Array) -> void:
	_fleet_message(fleet, type, params)
	_task_done(fleet, wp)


## The slot of a transferred design of the player with the same hull and parts, or -1.
static func _identical_transferred(player: Player, design: Design) -> int:
	for d in player.ship_designs:
		if not d.transferred or d.hull != design.hull or d.parts.size() != design.parts.size():
			continue
		var same := true
		for i in d.parts.size():
			var a := d.parts[i]
			var b := design.parts[i]
			if a.count != b.count or (a.count != 0 and a.part != b.part):
				same = false
				break
		if same:
			return d.slot
	return -1


## Ends the task of the fleet's current waypoint. A fleet with ships and no further waypoints whose
## waypoint had a task also gets "completed its assigned orders" (S21; an earlier one for the fleet
## this turn is replaced).
func _task_done(fleet: Fleet, wp: Waypoint) -> void:
	if fleet.waypoints.size() == 1 and fleet.ship_count() > 0 and wp.task != "none":
		var goto := {"fleet": fleet.number, "owner": fleet.owner}
		var list: Array = (
			_state.messages[fleet.owner] if fleet.owner < _state.messages.size() else []
		)
		var kept := list.filter(
			func(m: Dictionary) -> bool:
				return m["type"] != "message.fleet.completed" or m["goto"] != goto
		)
		if fleet.owner < _state.messages.size():
			_state.messages[fleet.owner] = kept
		_fleet_message(fleet, "fleet.completed", [_fleet_word(fleet)])
	wp.task = "none"
	wp.task_data = {}


func _record(fleet: Fleet, planet: Planet, colonists: int) -> void:
	_combat.record(fleet, planet, colonists)


## S02 5c and 16d: ground combat for the colonists landed since the last resolution (S17).
func resolve() -> void:
	_combat.resolve()
