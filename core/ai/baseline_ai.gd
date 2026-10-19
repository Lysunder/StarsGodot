class_name BaselineAi
extends BaselineBase
## Our own computer player (spec S22 "The baseline brain"): it grows an economy and spreads out.
## Each turn, in this order: research settings, relations, the default queue for new colonies,
## designs, the threats to its planets, orders to its fleets (colony ships, scouts, war fleets,
## troop transports, mineral haulers), then each planet's queue. It reads only its view (its own
## things, and other planets as it knows them) and draws nothing.
##
## Its settings (personality `params`, per level in `levels`) and their defaults are declared
## in BaselineBase.SETTINGS.


func play(ctx: AiContext) -> void:
	_ctx = ctx
	_state = ctx.view.state
	_me = ctx.me()
	_designs = BaselineDesigns.new(ctx.view, ctx.content)
	_count_planets()
	_research()
	_update_relations()
	if _state.turn == 0:
		_defaults()
	_update_designs()
	_update_dock_design()
	_update_warship_design()
	_update_bomber_design()
	_update_transport_design()
	_update_hauler_design()
	_note_destinations()
	_find_threats()
	for fleet in _state.fleets_of(_me.index):
		if _is_colony_fleet(fleet):
			_send_colony_ship(fleet)
		elif _is_scout(fleet):
			_send_scout(fleet)
		elif _is_war_fleet(fleet):
			_send_war_fleet(fleet)
		elif _is_transport(fleet):
			_send_transport(fleet)
		elif _is_hauler(fleet):
			_send_hauler(fleet)
	for planet in _state.planets:
		if planet.owner == _me.index:
			_plan_queue(planet)


func _count_planets() -> void:
	for planet in _state.planets:
		if planet.owner == _me.index:
			_owned_planets += 1
		elif not _info(planet.id)["known"]:
			_unknown_planets += 1


## The research budget, and the field: the lowest level, ties by FIELD_PRIORITY.
func _research() -> void:
	var order := PartRules.tech_order(_ctx.content)
	var best := -1
	for field: String in FIELD_PRIORITY:
		var i: int = order[field]
		if best < 0 or _me.tech_levels[i] < _me.tech_levels[best]:
			best = i
	var percent := _ctx.param("research_pct")
	if (
		_me.research_percent == percent
		and _me.research_field == best
		and _me.next_research_field == Player.NEXT_FIELD_LOWEST
	):
		return
	_ctx.order(
		{"type": "research", "percent": percent, "field": best, "next": Player.NEXT_FIELD_LOWEST}
	)


## Relations: a player met in battle (a battle of just the two, or with a player not its friend)
## is an enemy from then on, kept in the working memory; with alliances, the other computer
## players are friends; everyone else keeps the relation the player has.
func _update_relations() -> void:
	var memory: Array = _me.knowledge.get(OrderRules.AI_MEMORY_KEY, [])
	var hostile := int(memory[HOSTILE_WORD]) if memory.size() > HOSTILE_WORD else 0
	_relations.clear()
	for b: Dictionary in BattleReplay.battles(_ctx.view):
		var players: Array = b.get("players", [])
		for q: int in players:
			if q != _me.index and (players.size() == 2 or _relation(q) != FRIEND):
				hostile |= 1 << q
	var wanted: Array[String] = []
	for q in _state.players.size():
		var r := _relation(q)
		if q != _me.index:
			if hostile & (1 << q):
				r = ENEMY
			elif _state.settings.computer_alliances and not _state.player(q).is_human():
				r = FRIEND
		wanted.append(r)
	_relations = wanted
	if Array(wanted) != Array(_me.relations):
		_ctx.order({"type": "player_relations", "relations": wanted})
	var words: Array = [] if hostile == 0 else [MEMORY_BYTES, hostile]
	if words != memory:
		_ctx.order({"type": "ai_memory", "words": words})


## New colonies build factories and mines.
func _defaults() -> void:
	(
		_ctx
		. order(
			{
				"type": "player_defaults",
				"leftover_to_research": false,
				"queue": [_item(AUTO_FACTORIES, AUTO_COUNT), _item(AUTO_MINES, AUTO_COUNT)],
			}
		)
	)


## Where the player's fleets are already going.
func _note_destinations() -> void:
	_colony_targets.clear()
	_scout_targets.clear()
	for fleet in _state.fleets_of(_me.index):
		if fleet.waypoints.size() < 2 or fleet.waypoints[-1].target != "planet":
			continue
		var target := fleet.waypoints[-1].target_id
		if _is_colony_fleet(fleet):
			_colony_targets[target] = true
		elif _is_scout(fleet):
			_scout_targets[target] = true


## A colony ship: load colonists where it is (the player's populated planet), then go to the best
## planet it can reach and colonize it; at its target, colonize.
func _send_colony_ship(fleet: Fleet) -> void:
	if _busy(fleet):
		return
	var here := _state.planet(fleet.planet) if fleet.planet >= 0 else null
	if here != null and here.owner < 0 and fleet.cargo[Fleet.CARGO_COLONISTS] > 0:
		_order_waypoint0_colonize(fleet, here)
		return
	if fleet.cargo[Fleet.CARGO_COLONISTS] == 0:
		if here == null or here.owner != _me.index:
			# empty away from home (its target was taken): back to the nearest planet with people
			var home := _nearest_populated(fleet)
			if home >= 0:
				_go(fleet, home, "none")
			return
		var share := here.population * _ctx.param("colonists_share_pct") / 100
		var cargo_load := mini(_cargo_room(fleet), share)
		if cargo_load <= 0:
			return
		(
			_ctx
			. order(
				{
					"type": "cargo_transfer",
					"fleet": fleet.number,
					"other": {"planet": here.id},
					"amounts": [0, 0, 0, cargo_load, 0],
				}
			)
		)
	var target := _best_colony_target(fleet)
	if target < 0:
		return
	_colony_targets[target] = true
	_go(fleet, target, "colonize")


## Colonize the unowned planet the fleet is already at (waypoint 0's task).
func _order_waypoint0_colonize(fleet: Fleet, planet: Planet) -> void:
	var wp := _waypoint_to(planet, "colonize", fleet.waypoints[0].warp)
	_ctx.order({"type": "waypoint_change", "fleet": fleet.number, "index": 0, "waypoint": wp})


## The unowned planet with the best value for the player within reach, nearest first on ties;
## -1 when none is worth it.
func _best_colony_target(fleet: Fleet) -> int:
	var best := -1
	var best_value := _ctx.param("min_value") - 1
	var best_d2 := 0
	for planet in _state.planets:
		if _colony_targets.has(planet.id) or planet.owner == _me.index:
			continue
		var info := _info(planet.id)
		if not info["known"] or info["owner"] >= 0:
			continue
		var value: int = info["habitability"]
		var d2 := _d2(fleet.x, fleet.y, planet.x, planet.y)
		if value < best_value or (value == best_value and best >= 0 and d2 >= best_d2):
			continue
		if _warp_for(fleet, planet) == 0:
			continue
		best = planet.id
		best_value = value
		best_d2 = d2
	return best


## A scout goes to the nearest planet the player has not scanned and no other scout is heading
## for, if it can get there and back to a dock of its own on its fuel; otherwise it goes to the
## nearest such dock to refuel.
func _send_scout(fleet: Fleet) -> void:
	if _busy(fleet):
		return
	var best := -1
	var best_d2 := 0
	var best_warp := 0
	for planet in _state.planets:
		if _scout_targets.has(planet.id) or planet.owner == _me.index:
			continue
		if _info(planet.id)["known"]:
			continue
		var d2 := _d2(fleet.x, fleet.y, planet.x, planet.y)
		if best >= 0 and d2 >= best_d2:
			continue
		var dock := _nearest_dock(planet.x, planet.y)
		if dock == null:
			continue
		var there_and_back := (
			_distance(fleet.x, fleet.y, planet.x, planet.y)
			+ _distance(planet.x, planet.y, dock.x, dock.y)
		)
		var warp := _warp_covering(fleet, there_and_back)
		if warp == 0:
			continue
		best = planet.id
		best_d2 = d2
		best_warp = warp
	if best < 0:
		var dock := _nearest_dock(fleet.x, fleet.y)
		if dock == null or dock.id == fleet.planet:
			return
		best = dock.id
		best_warp = 0
	_scout_targets[best] = true
	_go(fleet, best, "none", best_warp)


## Warships: away from home with nothing left to fight where they are, back to the homeworld; at
## the homeworld, all the warships there join one fleet, which attacks the nearest enemy planet it
## is strong enough for once it has `attack_ships` ships.
func _send_war_fleet(fleet: Fleet) -> void:
	if _busy(fleet) or _merged.has(fleet.number):
		return
	var home := _state.planet(_me.homeworld)
	if home == null or home.owner != _me.index:
		home = _state.planet(_nearest_populated(fleet)) if _nearest_populated(fleet) >= 0 else null
	if home == null:
		return
	if fleet.planet != home.id:
		var here := _info(fleet.planet) if fleet.planet >= 0 else {}
		if not here.is_empty() and here["owner"] == _me.index and _is_threatened(fleet.planet):
			return
		if here.is_empty() or here["owner"] < 0 or here["owner"] == _me.index:
			_go(fleet, home.id, "none")
		return
	var others: Array[int] = []
	var ships := fleet.ship_count()
	var strength := _fleet_strength(fleet)
	for other in _state.fleets_of(_me.index):
		if other != fleet and other.planet == home.id and _is_war_fleet(other) and not _busy(other):
			others.append(other.number)
			_merged[other.number] = true
			ships += other.ship_count()
			strength += _fleet_strength(other)
	if not others.is_empty():
		_ctx.order({"type": "fleet_merge", "fleet": fleet.number, "fleets": others})
	for planet in _threatened:
		if planet.id == home.id:
			return
		if _warp_for(fleet, planet) > 0:
			_go(fleet, planet.id, "none")
			return
	if ships < _ctx.param("attack_ships"):
		return
	var target := _attack_target(home, fleet, strength)
	if target >= 0:
		_go(fleet, target, "none")


## The player's planets with a war fleet of another player within `defense_range` this turn,
## nearest the homeworld first.
func _find_threats() -> void:
	_threatened.clear()
	if _me.index >= _state.views.size() or not _state.views[_me.index] is Dictionary:
		return
	var seen: Dictionary = _state.views[_me.index].get("fleets", {})
	var threats: Array[Fleet] = []
	for key: String in seen:
		var parts := key.split("/")
		var enemy := _state.fleet(int(parts[0]), int(parts[1]))
		if enemy == null or not _looks_armed(enemy) or _relation(enemy.owner) == FRIEND:
			continue
		# a fleet at a planet of its own (as the player knows it) is at home, not a threat
		if enemy.planet >= 0 and _info(enemy.planet)["owner"] == enemy.owner:
			continue
		threats.append(enemy)
	if threats.is_empty():
		return
	var reach := _ctx.param("defense_range")
	for planet in _state.planets:
		if planet.owner != _me.index:
			continue
		for enemy in threats:
			if _d2(planet.x, planet.y, enemy.x, enemy.y) <= reach * reach:
				_threatened.append(planet)
				break
	var home := _state.planet(_me.homeworld)
	if home != null:
		_threatened.sort_custom(
			func(a: Planet, b: Planet) -> bool:
				return _d2(a.x, a.y, home.x, home.y) < _d2(b.x, b.y, home.x, home.y)
		)


## A troop transport: empty at one of the player's planets with people, it picks the nearest
## planet known to be an enemy's, without a starbase, that it can reach and take with the
## troops it can carry, loads them and unloads them there (an invasion, S17); empty elsewhere, it
## goes back to the nearest planet with people; still loaded at home with nowhere to go, it lands
## its colonists.
func _send_transport(fleet: Fleet) -> void:
	if _busy(fleet):
		return
	var here := _state.planet(fleet.planet) if fleet.planet >= 0 else null
	var aboard := fleet.cargo[Fleet.CARGO_COLONISTS]
	if here == null or here.owner != _me.index:
		if aboard == 0:
			var back := _nearest_populated(fleet)
			if back >= 0:
				_go(fleet, back, "none")
		return
	var spare := here.population / 2
	var best := -1
	var best_d2 := 0
	var best_troops := 0
	for planet in _state.planets:
		if _invasion_targets.has(planet.id):
			continue
		var info := _info(planet.id)
		if not info["known"] or not _is_enemy(info["owner"]):
			continue
		# only on a fresh report: an old one undercounts the people and defenses now there; and
		# not where the estimate hides the people (an owned planet estimated at none)
		if int(info["report_age"]) > _ctx.param("invasion_report_age"):
			continue
		if int(info["population"]) <= 0:
			continue
		if int(info.get("starbase_design", -1)) >= 0:
			continue
		var d2 := _d2(fleet.x, fleet.y, planet.x, planet.y)
		if best >= 0 and d2 >= best_d2:
			continue
		var warp := _warp_for(fleet, planet)
		if warp == 0:
			continue
		# near enough that the planet doesn't outgrow the troops on the way, padded for its growth
		# (compounded each year of the trip)
		var years := ceili(float(_distance(fleet.x, fleet.y, planet.x, planet.y)) / (warp * warp))
		if years > _ctx.param("invasion_max_years"):
			continue
		var troops := _troops_needed(info)
		for y in years:
			troops = troops * (100 + GROWTH_PER_YEAR_PCT) / 100
		if troops <= 0 or troops > _cargo_room(fleet) + aboard or troops > spare + aboard:
			continue
		best = planet.id
		best_d2 = d2
		best_troops = troops
	if best < 0:
		if aboard > 0:
			_transfer(fleet, here, -aboard)
		return
	_invasion_targets[best] = true
	if best_troops != aboard:
		_transfer(fleet, here, best_troops - aboard)
	var wp := _waypoint_to(
		_state.planet(best), "transport", maxi(_warp_for(fleet, _state.planet(best)), 1)
	)
	var cargo := []
	for c in Fleet.CARGO_FUEL + 1:
		cargo.append(
			{"action": "unload_all" if c == Fleet.CARGO_COLONISTS else "none", "amount": 0}
		)
	wp["task_data"] = {"cargo": cargo}
	_ctx.order({"type": "waypoint_add", "fleet": fleet.number, "index": 1, "waypoint": wp})


## A mineral hauler without orders: from the player's planet with the most surface minerals it
## brings all it can carry to the planet with `warship_min_population` people (one that builds
## ships) that is shortest of its scarcest mineral: load-all at the source, unload-all at the
## destination, both as transport tasks. Nothing when the source has less than half its room.
func _send_hauler(fleet: Fleet) -> void:
	if _busy(fleet):
		return
	var shipyard: Planet = null
	var scarcest := 0
	for planet in _state.planets:
		if planet.owner != _me.index:
			continue
		if planet.population < _ctx.param("warship_min_population"):
			continue
		var low := mini(planet.surface[0], mini(planet.surface[1], planet.surface[2]))
		if shipyard == null or low < scarcest:
			shipyard = planet
			scarcest = low
	if shipyard == null:
		return
	var source: Planet = null
	var most := 0
	for planet in _state.planets:
		if planet.owner != _me.index or planet == shipyard:
			continue
		var total := planet.surface[0] + planet.surface[1] + planet.surface[2]
		if total > most and _warp_for(fleet, planet) > 0:
			source = planet
			most = total
	if source == null or most * 2 < _cargo_room(fleet):
		return
	var cargo_load := []
	var unload := []
	for c in Fleet.CARGO_FUEL + 1:
		var mineral := c < Fleet.CARGO_COLONISTS
		cargo_load.append({"action": "load_all" if mineral else "none", "amount": 0})
		unload.append({"action": "unload_all" if mineral else "none", "amount": 0})
	var there := _waypoint_to(source, "transport", maxi(_warp_for(fleet, source), 1))
	there["task_data"] = {"cargo": cargo_load}
	var back := _waypoint_to(shipyard, "transport", there["warp"])
	back["task_data"] = {"cargo": unload}
	_ctx.order({"type": "waypoint_add", "fleet": fleet.number, "index": 1, "waypoint": there})
	_ctx.order({"type": "waypoint_add", "fleet": fleet.number, "index": 2, "waypoint": back})


## The colonists (kT, units of 100) that take a planet as the player knows it (S17 "Ground
## combat"): its population at the top of the estimate (+1/8), over the share of troops its
## defenses let through and the race's troop strength, times TROOP_MARGIN_PCT; 0 when the race
## can't invade.
func _troops_needed(info: Dictionary) -> int:
	var strength := RaceMath.trait_param(_me.race, _ctx.content, "invasion.troops_pct", 100)
	if strength <= 0:
		return 0
	var population: int = info["population"]
	if population <= 0:
		return 1
	# a defense class c lets about (101 - 6c)% of bombs through (S15 "Estimates"); troops get
	# through U + (1 - U) / 4 of the way
	var defense: int = info.get("defense_estimate", 0)
	var through := 100 if defense == 0 else clampi(101 - 6 * defense, 0, 100)
	var troops_through := through + (100 - through) / 4
	var top := population + population / 8
	return top * 100 * 100 * TROOP_MARGIN_PCT / 100 / (strength * maxi(troops_through, 1)) + 1


## The planet nearest `from` the player knows to belong to an enemy, that the fleet can reach and
## is strong enough for (`strength` against `_enemy_strength`), -1 for none.
func _attack_target(from: Planet, fleet: Fleet, strength: int) -> int:
	var best := -1
	var best_d2 := 0
	for planet in _state.planets:
		if planet.owner == _me.index:
			continue
		var info := _info(planet.id)
		if not _is_enemy(info["owner"]):
			continue
		var d2 := _d2(from.x, from.y, planet.x, planet.y)
		if best >= 0 and d2 >= best_d2:
			continue
		if _warp_for(fleet, planet) == 0:
			continue
		if not _strong_enough(strength, _enemy_strength(planet)):
			continue
		best = planet.id
		best_d2 = d2
	return best


## A scout and a colony ship of the best parts the player has: saved in a free slot when the
## player has none of that kind, or when it is better than the best one it has (faster, or as
## fast and going BaselineDesigns.BETTER_PCT as far).
func _update_designs() -> void:
	var taken := {}
	for kind in [BaselineDesigns.SCOUT, BaselineDesigns.COLONY]:
		var made := _designs.build(kind)
		if made == null:
			continue
		var have := _best_design(kind)
		if have != null and not _designs.better(made, have):
			continue
		var slot := _free_slot(taken)
		if slot < 0:
			continue
		taken[slot] = true
		made.slot = slot
		made.turn_designed = _state.turn
		_new_designs[kind] = slot
		_made[slot] = made
		_ctx.order(
			{"type": "design_change", "starbase": false, "slot": slot, "design": made.to_dict()}
		)


## A warship design when the player has none, or the best it can make is WARSHIP_BETTER_PCT as
## strong as its best.
func _update_warship_design() -> void:
	var made := _designs.build(BaselineDesigns.WARSHIP)
	if made == null:
		return
	var have := _best_warship()
	if (
		have != null
		and _designs.strength(made) * 100 < _designs.strength(have) * WARSHIP_BETTER_PCT
	):
		return
	var taken := {}
	for slot in _made:
		taken[slot] = true
	var slot := _free_slot(taken)
	if slot < 0:
		return
	made.slot = slot
	made.turn_designed = _state.turn
	_new_designs[BaselineDesigns.WARSHIP] = slot
	_made[slot] = made
	_ctx.order({"type": "design_change", "starbase": false, "slot": slot, "design": made.to_dict()})


## A bomber design when the player has none, or the best it can make is WARSHIP_BETTER_PCT as
## strong as its best.
func _update_bomber_design() -> void:
	var made := _designs.build(BaselineDesigns.BOMBER)
	if made == null:
		return
	var have := _best_bomber()
	if (
		have != null
		and _designs.bomb_power(made) * 100 < _designs.bomb_power(have) * WARSHIP_BETTER_PCT
	):
		return
	var taken := {}
	for slot in _made:
		taken[slot] = true
	var slot := _free_slot(taken)
	if slot < 0:
		return
	made.slot = slot
	made.turn_designed = _state.turn
	_new_designs[BaselineDesigns.BOMBER] = slot
	_made[slot] = made
	_ctx.order({"type": "design_change", "starbase": false, "slot": slot, "design": made.to_dict()})


## A mineral hauler design when the player has none, or one with WARSHIP_BETTER_PCT of the room
## of its best.
func _update_hauler_design() -> void:
	var made := _designs.build(BaselineDesigns.HAULER)
	if made == null:
		return
	var have := _best_freighter(_is_hauler_design)
	if have != null and _designs.cargo(made) * 100 < _designs.cargo(have) * WARSHIP_BETTER_PCT:
		return
	var taken := {}
	for slot in _made:
		taken[slot] = true
	var slot := _free_slot(taken)
	if slot < 0:
		return
	made.slot = slot
	made.turn_designed = _state.turn
	_new_designs[BaselineDesigns.HAULER] = slot
	_made[slot] = made
	_ctx.order({"type": "design_change", "starbase": false, "slot": slot, "design": made.to_dict()})


## A troop transport design when the player has none, or one with WARSHIP_BETTER_PCT of the
## room of its best.
func _update_transport_design() -> void:
	var made := _designs.build(BaselineDesigns.TRANSPORT)
	if made == null:
		return
	var have := _best_transport()
	if have != null and _designs.cargo(made) * 100 < _designs.cargo(have) * WARSHIP_BETTER_PCT:
		return
	var taken := {}
	for slot in _made:
		taken[slot] = true
	var slot := _free_slot(taken)
	if slot < 0:
		return
	made.slot = slot
	made.turn_designed = _state.turn
	_new_designs[BaselineDesigns.TRANSPORT] = slot
	_made[slot] = made
	_ctx.order({"type": "design_change", "starbase": false, "slot": slot, "design": made.to_dict()})


## A dock design on the cheapest hull that docks, unless the player has one on that hull.
func _update_dock_design() -> void:
	var have := _dock_design()
	if have != null and have.hull == _designs.cheapest_dock_hull():
		return
	var made := _designs.build(BaselineDesigns.DOCK)
	if made == null:
		return
	var limit := _ctx.content.constant("constant.limits.starbase_designs")
	for slot in limit:
		if _me.starbase_design(slot) == null:
			made.slot = slot
			made.turn_designed = _state.turn
			_new_dock = made
			_ctx.order(
				{"type": "design_change", "starbase": true, "slot": slot, "design": made.to_dict()}
			)
			return


## A planet's queue, on planets with people to spare (`colony_min_population`): a colony ship
## while the player has fewer than `colony_ships` + one per COLONIES_PER_SHIP planets and there
## are places to settle, a scout while it has fewer than `scouts` + one per PLANETS_PER_SCOUT
## planets and planets it has never scanned; then factories and mines. Sent only when it
## differs from the planet's queue.
func _plan_queue(planet: Planet) -> void:
	var items: Array = []
	var spare := planet.population >= _ctx.param("colony_min_population")
	var colony_slot := _design_slot(BaselineDesigns.COLONY)
	if (
		spare
		and colony_slot >= 0
		and _affords(planet, colony_slot)
		and _ships(BaselineDesigns.COLONY, planet) < _colony_quota()
		and _has_colony_targets()
	):
		items.append(_design_item(colony_slot, 1))
		_planned[BaselineDesigns.COLONY] = _planned.get(BaselineDesigns.COLONY, 0) + 1
	var scout_slot := _design_slot(BaselineDesigns.SCOUT)
	if (
		spare
		and scout_slot >= 0
		and _affords(planet, scout_slot)
		and _ships(BaselineDesigns.SCOUT, planet) < _scout_quota()
		and _unknown_planets > 0
	):
		items.append(_design_item(scout_slot, 1))
		_planned[BaselineDesigns.SCOUT] = _planned.get(BaselineDesigns.SCOUT, 0) + 1
	var warship_slot := _design_slot(BaselineDesigns.WARSHIP)
	if (
		_state.turn >= _ctx.param("war_turn")
		and warship_slot >= 0
		and planet.population >= _ctx.param("warship_min_population")
		and _affords(planet, warship_slot)
		and _ships(BaselineDesigns.WARSHIP, planet) < _warship_quota()
	):
		items.append(_design_item(warship_slot, 1))
		_planned[BaselineDesigns.WARSHIP] = _planned.get(BaselineDesigns.WARSHIP, 0) + 1
	var bomber_slot := _design_slot(BaselineDesigns.BOMBER)
	if (
		_state.turn >= _ctx.param("war_turn")
		and bomber_slot >= 0
		and planet.population >= _ctx.param("warship_min_population")
		and _affords(planet, bomber_slot)
		and _ships(BaselineDesigns.BOMBER, planet) < _bomber_quota()
	):
		items.append(_design_item(bomber_slot, 1))
		_planned[BaselineDesigns.BOMBER] = _planned.get(BaselineDesigns.BOMBER, 0) + 1
	var hauler_slot := _design_slot(BaselineDesigns.HAULER)
	if (
		_state.turn >= _ctx.param("haul_turn")
		and hauler_slot >= 0
		and planet.population >= _ctx.param("warship_min_population")
		and _affords(planet, hauler_slot)
		and _ships(BaselineDesigns.HAULER, planet) < _hauler_quota()
	):
		items.append(_design_item(hauler_slot, 1))
		_planned[BaselineDesigns.HAULER] = _planned.get(BaselineDesigns.HAULER, 0) + 1
	var transport_slot := _design_slot(BaselineDesigns.TRANSPORT)
	if (
		_state.turn >= _ctx.param("war_turn")
		and transport_slot >= 0
		and planet.population >= _ctx.param("warship_min_population")
		and _affords(planet, transport_slot)
		and _ships(BaselineDesigns.TRANSPORT, planet) < _transport_quota()
	):
		items.append(_design_item(transport_slot, 1))
		_planned[BaselineDesigns.TRANSPORT] = _planned.get(BaselineDesigns.TRANSPORT, 0) + 1
	if _wants_dock(planet):
		items.append(
			{"item": "", "design": _dock_design().slot, "starbase": true, "count": 1, "progress": 0}
		)
		_planned_docks.append(planet)
	items.append(_item(AUTO_FACTORIES, AUTO_COUNT))
	items.append(_item(AUTO_MINES, AUTO_COUNT))
	if _info(planet.id)["habitability"] < FULL_VALUE:
		items.append(_item(AUTO_TERRAFORM, AUTO_COUNT))
	if planet.population >= _ctx.param("defense_min_population"):
		items.append(_item(AUTO_DEFENSES, AUTO_COUNT))
	if _same_queue(planet, items):
		return
	_ctx.order({"type": "production_queue", "planet": planet.id, "items": items})


## A dock: on a planet without a starbase, with `dock_min_population` people and the minerals for
## it, at least `dock_spacing` light-years from the player's docks (those queued this turn too).
func _wants_dock(planet: Planet) -> bool:
	var d := _dock_design()
	if d == null or planet.starbase != null:
		return false
	if planet.population < _ctx.param("dock_min_population") or not _affords_design(planet, d):
		return false
	var near := _nearest_dock(planet.x, planet.y, true)
	return (
		near == null or _distance(planet.x, planet.y, near.x, near.y) >= _ctx.param("dock_spacing")
	)


## Whether any known unowned planet is worth settling and not already a colony ship's target.
func _has_colony_targets() -> bool:
	for planet in _state.planets:
		if planet.owner == _me.index or _colony_targets.has(planet.id):
			continue
		var info := _info(planet.id)
		if info["known"] and info["owner"] < 0 and info["habitability"] >= _ctx.param("min_value"):
			return true
	return false
