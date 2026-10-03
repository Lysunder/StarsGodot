class_name StartingSetup
extends RefCounted
## S07 steps 9.5-12 for a universe made by UniverseGenerator: starting tech, homeworlds, starbase
## and ship designs, starting fleets, the extra planet, battle plans, wormholes and relations.
##
## The per-trait differences are content: `starting_setup` definitions (one per trait),
## `starting_design` templates, `part_upgrade` lists and `battle_plan_default` plans.

const STARTING_DESIGN_TURN := 1
const HOMEWORLD_INSTALLATIONS := 10
const MIN_HOMEWORLD_CONCENTRATION := 30
const COMPUTER_LEFTOVER := 50
const DEFAULT_MASS_DRIVER_WARP := 4
const DEFAULT_RESEARCH_PERCENT := 15
const OBJECT_LIMIT := 512
const EXTRA_PLANET_MIN_HAB := 10
const EXTRA_PLANET_TRIES := 100

var _gen: UniverseGenerator
var _state: GameState
var _content: ContentRegistry
var _rng: StarsRandom
var _tech_order: Dictionary
var _setups: Dictionary = {}  # trait id -> starting_setup definition


func _init(gen: UniverseGenerator, state: GameState) -> void:
	_gen = gen
	_state = state
	_content = gen.content
	_rng = gen.rng()
	_tech_order = PartRules.tech_order(_content)
	for id in _content.ids("starting_setup"):
		var def := _content.get_def("starting_setup", id)
		_setups[def["trait"]] = def


func run() -> void:
	for i in _state.players.size():
		_starting_tech(_state.players[i], i)
	for p in _state.players:
		_homeworld(p)
	for p in _state.players:
		_starting_fleets(p)
	_finish()


# --- Step 9.5: starting tech -----------------------------------------------------------------


func _starting_tech(p: Player, index: int) -> void:
	p.index = index
	p.homeworld = _gen.homeworlds[index]
	var levels: Array[int] = [0, 0, 0, 0, 0, 0]
	var tech: Dictionary = _setup(p.race.primary_trait).get("tech", {})
	for field: String in tech:
		levels[_tech_order[field]] = tech[field]
	if p.race.techs_start_at_3:
		var floor_level := _param(
			p, "start.tech_floor", _content.constant("constant.start.tech_floor")
		)
		for f in levels.size():
			if levels[f] < floor_level and p.race.research_costs[f] == RaceMath.RESEARCH_EXPENSIVE:
				levels[f] = floor_level
	for id in p.race.lesser_traits:
		var setup := _setup(id)
		_add_tech(levels, setup.get("tech_bonus", {}))
		if not _gen.settings.tutorial:
			_add_tech(levels, setup.get("tech_bonus_outside_tutorial", {}))
	p.tech_levels = levels
	p.research_points.assign([0, 0, 0, 0, 0, 0])
	p.research_field = 0
	p.next_research_field = Player.NEXT_FIELD_SAME
	if p.is_human():
		p.research_percent = DEFAULT_RESEARCH_PERCENT
	var relations: Array[String] = []
	for k in _state.players.size():
		relations.append("neutral")
	p.relations = relations


func _add_tech(levels: Array[int], bonus: Dictionary) -> void:
	for field: String in bonus:
		levels[_tech_order[field]] += int(bonus[field])


# --- Step 10: homeworlds ---------------------------------------------------------------------


func _homeworld(p: Player) -> void:
	var hw := _state.planet(p.homeworld)
	var setup := _setup(p.race.primary_trait)
	hw.owner = p.index
	hw.homeworld = true
	hw.artifact = null
	hw.has_scanner = true
	hw.starbase = Starbase.new()
	hw.mines = HOMEWORLD_INSTALLATIONS
	hw.factories = HOMEWORLD_INSTALLATIONS
	hw.defenses = HOMEWORLD_INSTALLATIONS
	hw.population = _param(p, "start.population", _content.constant("constant.start.population"))
	hw.surface.assign(_gen.template)
	for k in 3:
		hw.concentration[k] = maxi(_state.planets[0].concentration[k], MIN_HOMEWORLD_CONCENTRATION)
	var leftover := mini(
		RaceMath.advantage_points(p.race, _content),
		_content.constant("constant.start.leftover_cap")
	)
	if not p.is_human():
		leftover = COMPUTER_LEFTOVER
		if p.ai_level >= 3:
			hw.population += hw.population / 10
	if _gen.settings.accelerated_start:
		var growth := p.race.growth_rate * _param(p, "race.growth_rate_pct", 100) / 100
		hw.population = hw.population * ((growth + 5) * 2) / 10
	_spend_leftover(p, hw, leftover)
	if not setup.get("homeworld_installations", true):
		hw.mines = 0
		hw.factories = 0
		hw.defenses = 0
	for axis in 3:
		if p.race.is_immune(axis):
			hw.environment[axis] = 1 + _rng.random(99)
		else:
			var low := p.race.hab_low[axis]
			hw.environment[axis] = low + (p.race.hab_high[axis] - low) / 2
	hw.environment_original.assign(hw.environment)
	_starbase_designs(p, setup)
	hw.starbase.design = setup.get("homeworld_starbase", 0)
	hw.mass_driver_target = -1
	hw.mass_driver_warp = setup.get("homeworld_mass_driver_warp", DEFAULT_MASS_DRIVER_WARP)


func _spend_leftover(p: Player, hw: Planet, leftover: int) -> void:
	match p.race.leftover_points:
		"concentrations":
			_concentration_bonus(hw, leftover)
		"mines":
			hw.mines += leftover / 2
		"factories":
			hw.factories += leftover / 5
		"defenses":
			hw.defenses += (leftover + 5) / 10
		_:
			var each := leftover * 10 / 4
			var least := 0
			for k in range(1, 3):
				if hw.surface[k] <= hw.surface[least]:
					least = k
			hw.surface[least] += each + leftover * 10 % 4
			for k in 3:
				hw.surface[k] += each
			if not p.is_human() and p.ai_level >= 2:
				_concentration_bonus(hw, leftover)


func _concentration_bonus(hw: Planet, leftover: int) -> void:
	var bonus := 1 if leftover == 1 or leftover == 2 else leftover / 2
	var lowest := 0
	for k in range(1, 3):
		if hw.concentration[k] < hw.concentration[lowest]:
			lowest = k
	hw.concentration[lowest] += bonus
	for k in 3:
		hw.concentration[k] += (bonus + 1) / 2


func _starbase_designs(p: Player, setup: Dictionary) -> void:
	for entry: Dictionary in setup.get("starbases", []):
		if not _conditions_met(entry, p):
			continue
		var design := _design_from(entry["design"], entry["slot"])
		var built := 1 if entry.get("built", true) else 0
		design.built = built
		design.remaining = built
		p.set_design(design, true)


# --- Step 11: starting fleets ----------------------------------------------------------------


func _starting_fleets(p: Player) -> void:
	var steps: Array = _setup(p.race.primary_trait).get("fleets", []).duplicate()
	for id in p.race.lesser_traits:
		steps.append_array(_setup(id).get("fleets", []))
	for step: Dictionary in steps:
		if not _conditions_met(step, p):
			continue
		if step.get("extra_planet", false):
			var extra := _extra_planet(p)
			_add_fleet(p, 0, extra)
			continue
		var slot := p.ship_designs.size()
		p.set_design(_design_from(step["design"], slot), false)
		for n in int(step.get("count", 1)):
			_add_fleet(p, slot, _state.planet(p.homeworld))
	for design in p.ship_designs:
		_upgrade_parts(p, design)
	if not _setup(p.race.primary_trait).get("homeworld_scanner", true):
		_state.planet(p.homeworld).has_scanner = false


func _add_fleet(p: Player, design_slot: int, at: Planet) -> void:
	var fleet := _state.add_fleet(p.index, _content.constant("constant.limits.fleets_per_player"))
	fleet.x = at.x
	fleet.y = at.y
	fleet.planet = at.id
	fleet.add_ships(design_slot, 1)
	var design := p.ship_design(design_slot)
	design.built += 1
	design.remaining += 1
	fleet.cargo[Fleet.CARGO_FUEL] = PartRules.fuel_capacity(design, _content)
	var wp := Waypoint.new(at.x, at.y)
	wp.target = "planet"
	wp.target_id = at.id
	fleet.waypoints.append(wp)


func _upgrade_parts(p: Player, design: Design) -> void:
	for slot in design.parts:
		if slot.part.is_empty():
			continue
		for id in _content.ids("part_upgrade"):
			var upgrade := _content.get_def("part_upgrade", id)
			if not (upgrade["from"] as Array).has(slot.part):
				continue
			for candidate: Dictionary in upgrade["candidates"]:
				if _candidate_ok(candidate, p, design):
					slot.part = candidate["part"]
					break
			break


func _candidate_ok(candidate: Dictionary, p: Player, design: Design) -> bool:
	if candidate.has("skip_on_hull") and design.hull == candidate["skip_on_hull"]:
		var axis := 2  # radiation
		var above: int = candidate.get("unless_radiation_center_above", 100)
		if not p.race.is_immune(axis) and p.race.hab_center[axis] <= above:
			return false
	return PartRules.available(_content.part(candidate["part"]), p, _tech_order)


## Picks, sets up and returns the extra starting planet (S07 step 11, "The extra planet").
func _extra_planet(p: Player) -> Planet:
	var hw := _state.planet(p.homeworld)
	var lo := _gen.width * 15 / 100
	var hi := _gen.width * 23 / 100
	var chosen: Planet = null
	var nearest: Planet = null
	var nearest_d2 := 10000000
	var in_band := 0
	for pl in _state.planets:
		if pl.owner != -1:
			continue
		var d2 := (pl.x - hw.x) * (pl.x - hw.x) + (pl.y - hw.y) * (pl.y - hw.y)
		if d2 < lo * lo or d2 > hi * hi:
			if chosen == null and d2 < nearest_d2:
				nearest = pl
				nearest_d2 = d2
		else:
			in_band += 1
			if _rng.random(in_band) == 0:
				chosen = pl
	if chosen == null:
		chosen = nearest
	chosen.mass_driver_target = -1
	chosen.mass_driver_warp = 5
	var tries := 0
	while Habitability.value(chosen.environment, p.race) < EXTRA_PLANET_MIN_HAB:
		if tries >= EXTRA_PLANET_TRIES:
			break
		tries += 1
		for axis in 3:
			chosen.environment[axis] = 2 + _rng.random(97)
		chosen.environment_original.assign(chosen.environment)
	if tries >= EXTRA_PLANET_TRIES:
		chosen.environment.assign(hw.environment)
		chosen.environment_original.assign(hw.environment_original)
	chosen.owner = p.index
	chosen.starbase = Starbase.new()
	chosen.starbase.design = 1
	chosen.artifact = null
	chosen.mines = 10
	chosen.factories = 4
	chosen.population = hw.population * 2 / 5
	for k in 3:
		chosen.surface[k] = 100 + _rng.random(200)
	chosen.has_scanner = true
	hw.population = hw.population * 4 / 5
	return chosen


# --- Step 12: finishing ----------------------------------------------------------------------


func _finish() -> void:
	var planet0 := _state.planets[0]
	if planet0.owner == -1:
		planet0.surface.assign([0, 0, 0])
	for p in _state.players:
		_battle_plans(p)
	_wormholes()
	var humans := 0
	for p in _state.players:
		if p.is_human() or not p.active:
			humans += 1
	if humans == 1:
		for p in _state.players:
			for k in _state.players.size():
				if k != p.index:
					p.relations[k] = "enemy"


func _battle_plans(p: Player) -> void:
	var plans := []
	var defs: Array = []
	for id in _content.ids("battle_plan_default"):
		defs.append(_content.get_def("battle_plan_default", id))
	defs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])
	for def: Dictionary in defs:
		(
			plans
			. append(
				{
					"number": def["order"],
					"name": _content.display_name(def["id"]),
					"tactic": def["tactic"],
					"primary_target": def["primary_target"],
					"secondary_target": def["secondary_target"],
					"attack": def["attack"],
				}
			)
		)
	p.battle_plans = plans


func _wormholes() -> void:
	var size := _gen.size_index()
	var pairs := _rng.random(_content.constant("constant.universe.wormholes_random_%d" % size))
	pairs += _content.constant("constant.universe.wormholes_base_%d" % size)
	for pair in pairs:
		var first: Wormhole = null
		for end in 2:
			var w := _state.add_wormhole(OBJECT_LIMIT)
			w.stability = _rng.random(3)
			if end == 1:
				w.other_end = first.number
				first.other_end = w.number
			else:
				first = w
			_place_wormhole(w)


func _place_wormhole(w: Wormhole) -> void:
	var best_score := 16
	var best: Array[int] = [0, 0]
	var score := 15
	for attempt in 100:
		w.x = 1000 + _rng.random(_gen.width)
		w.y = 1000 + _rng.random(_gen.width)
		score = Wormholes.score(_state, w, _gen.width)
		if score == 0:
			return
		if score < best_score:
			best_score = score
			best = [w.x, w.y]
	w.x = best[0]
	w.y = best[1]


# --- Helpers ---------------------------------------------------------------------------------


func _setup(trait_id: String) -> Dictionary:
	return _setups.get(trait_id, {})


func _param(p: Player, name: String, default: int) -> int:
	return RaceMath.trait_param(p.race, _content, name, default)


func _conditions_met(entry: Dictionary, p: Player) -> bool:
	if _gen.size_index() < int(entry.get("min_universe_size", 0)):
		return false
	if entry.get("outside_tutorial", false) and _gen.settings.tutorial:
		return false
	if entry.get("tutorial_only", false) and not _gen.settings.tutorial:
		return false
	if entry.get("human_only", false) and not p.is_human():
		return false
	var min_tech: Dictionary = entry.get("min_tech", {})
	for field: String in min_tech:
		if p.tech_levels[_tech_order[field]] < int(min_tech[field]):
			return false
	var below: Dictionary = entry.get("below_tech", {})
	for field: String in below:
		if p.tech_levels[_tech_order[field]] >= int(below[field]):
			return false
	var traits := PartRules.traits_of(p.race)
	for t: String in entry.get("forbidden_traits", []):
		if traits.has(t):
			return false
	return true


func _design_from(template_id: String, slot: int) -> Design:
	var def := _content.get_def("starting_design", template_id)
	var design := Design.new()
	design.slot = slot
	design.name = _content.display_name(template_id)
	design.hull = def["hull"]
	design.picture = PartRules.design_picture(def.get("picture", 0), _content.hull(design.hull))
	design.turn_designed = STARTING_DESIGN_TURN
	for s: Dictionary in def["slots"]:
		design.parts.append(DesignSlot.new(s.get("part", ""), s.get("count", 0)))
	return design
