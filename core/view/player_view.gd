class_name PlayerView
extends RefCounted
## What one player sees of a game (M11 UI): read-only summaries built from a state (normally the
## order preview) for the map and the panes. The UI reads only this and never the state.
##
## Visibility (M8, S15) is not built yet: with `reveal_all` on, every planet's details are shown;
## other players' fleets are never shown.

const YEAR_ZERO := 2400
const PICK_RADIUS := 6

var state: GameState
var content: ContentRegistry
var player: int = 0
var reveal_all: bool = true
## The ship designer's queries (M11 step 5).
var designer: DesignView


func _init(p_state: GameState, p_content: ContentRegistry, p_player: int) -> void:
	state = p_state
	content = p_content
	player = p_player
	designer = DesignView.new(p_state, p_content, p_player)


func me() -> Player:
	return state.player(player)


func year() -> int:
	return YEAR_ZERO + state.turn


func universe_width() -> int:
	return state.settings.universe_width


## Every planet: id, name, position, owner (-1 none) and whether it is the player's.
func planets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pl in state.planets:
		(
			out
			. append(
				{
					"id": pl.id,
					"name": pl.name,
					"x": pl.x,
					"y": pl.y,
					"owner": pl.owner,
					"mine": pl.owner == player,
					"population": pl.population if (pl.owner == player or reveal_all) else 0,
					"starbase": pl.starbase != null,
				}
			)
		)
	return out


## The details the planet pane shows; known=false when the player may not see them.
func planet_info(id: int) -> Dictionary:
	var pl := state.planet(id)
	var race := me().race
	var known := pl.owner == player or reveal_all
	var info := {
		"id": pl.id,
		"name": pl.name,
		"x": pl.x,
		"y": pl.y,
		"owner": pl.owner,
		"mine": pl.owner == player,
		"known": known,
		"homeworld": pl.homeworld,
	}
	if not known:
		return info
	var owner_race := state.player(pl.owner).race if pl.owner >= 0 else race
	(
		info
		. merge(
			{
				"environment": pl.environment.duplicate(),
				"environment_original": pl.environment_original.duplicate(),
				"habitability": PlanetEconomy.hab_value(pl, race),
				"max_population": PlanetEconomy.max_pop(pl, race, content),
				"population": pl.population,
				"surface": pl.surface.duplicate(),
				"concentration": pl.concentration.duplicate(),
			}
		)
	)
	if pl.owner < 0:
		return info
	(
		info
		. merge(
			{
				"growth": PlanetEconomy.next_population(pl, owner_race, content) - pl.population,
				"resources": PlanetEconomy.resources(pl, owner_race, content),
				"mines": pl.mines,
				"max_mines": PlanetEconomy.max_mines(pl, owner_race, content),
				"operable_mines": PlanetEconomy.effective_mines(pl, owner_race, content),
				"factories": pl.factories,
				"max_factories": PlanetEconomy.max_factories(pl, owner_race, content),
				"operable_factories":
				mini(pl.factories, PlanetEconomy.operable_factories(pl, owner_race, content)),
				"defenses": pl.defenses,
				"max_defenses": PlanetEconomy.max_defenses(pl, owner_race),
				"starbase": design_name(pl.owner, pl.starbase.design, true) if pl.starbase else "",
				"leftover_to_research": pl.leftover_to_research,
				"route": pl.route,
				"queue": queue_info(pl),
			}
		)
	)
	return info


## The planet's production queue as display rows.
func queue_info(pl: Planet) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q in pl.queue:
		var auto := false
		if not q.is_design():
			auto = bool(content.get_def("production_item", q.item).get("auto", false))
		(
			out
			. append(
				{
					"name": queue_item_name(pl.owner, q),
					"count": q.count,
					"progress": q.progress,
					"auto": auto,
				}
			)
		)
	return out


func queue_item_name(owner: int, q: QueueItem) -> String:
	if q.is_design():
		return design_name(owner, q.design, q.starbase)
	return content.display_name(q.item)


## What the planet's queue can take: standard items, then the player's ship designs (and
## starbase designs at a planet the player owns). Each: {label, order item fields}.
func production_inventory(id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pl := state.planet(id)
	if pl.owner != player:
		return out
	var items := []
	for item_id in content.ids("production_item"):
		items.append([int(content.get_def("production_item", item_id).get("order", 0)), item_id])
	items.sort()
	for pair: Array in items:
		(
			out
			. append(
				{
					"label": content.display_name(pair[1]),
					"item": pair[1],
					"design": -1,
					"starbase": false,
				}
			)
		)
	for d in me().ship_designs:
		out.append({"label": d.name, "item": "", "design": d.slot, "starbase": false})
	for d in me().starbase_designs:
		out.append(
			{"label": d.name + " (starbase)", "item": "", "design": d.slot, "starbase": true}
		)
	return out


func design_name(owner: int, slot: int, starbase: bool) -> String:
	var p := state.player(owner)
	var d := p.starbase_design(slot) if starbase else p.ship_design(slot)
	return d.name if d != null else "?"


## The player's fleets.
func fleets() -> Array[Fleet]:
	return state.fleets_of(player)


func fleet_name(f: Fleet) -> String:
	if not f.name.is_empty():
		return f.name
	var first := "Fleet"
	if not f.stacks.is_empty():
		first = design_name(f.owner, f.stacks[0].design, false)
	return "%s #%d" % [first, f.number + 1]


## The details the fleet pane shows, including each leg's distance, years and fuel estimate, and
## whether the fleet can't move (no full engine slot) or runs short of fuel on the way.
func fleet_info(number: int) -> Dictionary:
	var f := state.fleet(player, number)
	if f == null:
		return {}
	var owner := me()
	var ships: Array[Dictionary] = []
	var cargo_capacity := 0
	for stack in f.stacks:
		var d := owner.ship_design(stack.design)
		ships.append({"design": stack.design, "name": d.name, "count": stack.count})
		cargo_capacity += stack.count * PartRules.cargo_capacity(d, content)
	var waypoints: Array[Dictionary] = []
	var fuel := f.cargo[Fleet.CARGO_FUEL]
	var years := 0
	for i in f.waypoints.size():
		var wp := f.waypoints[i]
		var row := {
			"x": wp.x,
			"y": wp.y,
			"target": wp.target,
			"target_owner": wp.target_owner,
			"target_id": wp.target_id,
			"label": _waypoint_label(wp),
			"warp": wp.warp,
			"task": wp.task,
			"task_data": wp.task_data.duplicate(true),
		}
		if i > 0:
			var prev := f.waypoints[i - 1]
			var distance := Vector2(wp.x - prev.x, wp.y - prev.y).length()
			var whole := int(distance + Movement.DISTANCE_ROUND_UP)
			var need := (
				Movement.fuel_needed(f, owner, wp.warp, whole, content) if wp.warp > 0 else 0
			)
			var stuck := need >= Movement.CANNOT_MOVE
			if not stuck:
				fuel -= need
			if wp.warp > 0:
				years += ceili(distance / float(wp.warp * wp.warp))
			(
				row
				. merge(
					{
						"distance": distance,
						"fuel": 0 if stuck else need,
						"fuel_left": fuel,
						"years": years,
						"cannot_move": stuck and whole > 0,
						"short_of_fuel": fuel < 0,
					}
				)
			)
		waypoints.append(row)
	return {
		"number": f.number,
		"name": fleet_name(f),
		"x": f.x,
		"y": f.y,
		"planet": f.planet,
		"ships": ships,
		"cargo": f.cargo.duplicate(),
		"cargo_capacity": cargo_capacity,
		"fuel_capacity": Movement.fuel_capacity(f, owner, content),
		"waypoints": waypoints,
		"repeat": f.repeat,
		"battle_plan": f.battle_plan,
	}


func _waypoint_label(wp: Waypoint) -> String:
	match wp.target:
		"planet":
			return state.planet(wp.target_id).name
		"fleet":
			var f := state.fleet(wp.target_owner, wp.target_id)
			return fleet_name(f) if f != null else "fleet"
	return "Space (%d, %d)" % [wp.x, wp.y]


## Planets and own fleets within PICK_RADIUS of a point, nearest first: {kind, id}.
func objects_at(x: float, y: float, radius: float = PICK_RADIUS) -> Array[Dictionary]:
	var hits := []
	for pl in state.planets:
		var d := Vector2(pl.x - x, pl.y - y).length()
		if d <= radius:
			hits.append([d, 0, {"kind": "planet", "id": pl.id}])
	for f in fleets():
		var d := Vector2(f.x - x, f.y - y).length()
		if d <= radius:
			hits.append([d, 1, {"kind": "fleet", "id": f.number}])
	hits.sort()
	var out: Array[Dictionary] = []
	for h: Array in hits:
		out.append(h[2])
	return out


## Research settings and levels for the top bar and research dialog.
func research_info() -> Dictionary:
	var p := me()
	var fields: Array[Dictionary] = []
	var order := PartRules.tech_order(content)
	for field_id: String in order:
		var i: int = order[field_id]
		(
			fields
			. append(
				{
					"index": i,
					"name": content.display_name(field_id),
					"level": p.tech_levels[i],
					"points": p.research_points[i],
					"cost": ResearchRules.level_cost(p, i, content, state.settings.slow_tech),
				}
			)
		)
	fields.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["index"] < b["index"])
	return {
		"percent": p.research_percent,
		"field": p.research_field,
		"next": p.next_research_field,
		"fields": fields,
	}


## Total resources of the player's planets this year.
func total_resources() -> int:
	var total := 0
	for pl in state.planets:
		if pl.owner == player:
			total += PlanetEconomy.resources(pl, me().race, content)
	return total
