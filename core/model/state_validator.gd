class_name StateValidator
extends RefCounted
## Checks a loaded game state against the content it is played with (spec S03, "Saved form"):
## value ranges, references between objects, references to content, and the limits.
##
## The model classes already check types and order when they load; this adds everything that
## needs content or the whole state. Every problem is reported as "path: message".

const MAX_SEED := (1 << 53) - 1
const MAX_INSTALLATIONS := 4095
const MAX_STARBASE_DAMAGE := 4095
const MAX_DRIVER_WARP := 19
const MAX_STACK_DAMAGE := 499
const MAX_WARP := 11

var _content: ContentRegistry
var _state: GameState
var _errors: PackedStringArray = []
var _tech_fields: int = 0


static func validate(state: GameState, content: ContentRegistry) -> PackedStringArray:
	var v := StateValidator.new()
	v._content = content
	v._state = state
	v._tech_fields = content.ids("tech_field").size()
	v._run()
	return v._errors


## The race's own checks (traits, habitability, ranges), with paths relative to the race.
static func validate_race(race: Race, content: ContentRegistry) -> PackedStringArray:
	var v := StateValidator.new()
	v._content = content
	v._tech_fields = content.ids("tech_field").size()
	v._check_race(race, "")
	return v._errors


func _run() -> void:
	if _state.turn < 0:
		_err("/turn", "must not be negative")
	if _state.settings.universe_width < 1:
		_err("/settings/universe_width", "must be at least 1")
	if _state.rng.game_seed < 0 or _state.rng.game_seed > MAX_SEED:
		_err("/rng/game_seed", "must be 0 .. 2^53 - 1")
	if _state.players.size() > _limit("players"):
		_err("/players", "more than %d players" % _limit("players"))
	for p in _state.players:
		_check_player(p, "/players/%d" % p.index)
	for pl in _state.planets:
		_check_planet(pl, "/planets/%d" % pl.id)
	for i in _state.fleets.size():
		_check_fleet(_state.fleets[i], "/fleets/%d" % i)
	_check_space_objects()


# --- Players ---------------------------------------------------------------------------------


func _check_player(p: Player, path: String) -> void:
	_check_race(p.race, path + "/race")
	if p.homeworld != -1:
		_planet_ref(p.homeworld, path + "/homeworld")
	_list_range(
		p.tech_levels,
		_tech_fields,
		0,
		_content.constant("constant.research.max_level"),
		path + "/tech_levels"
	)
	_list_range(p.research_points, _tech_fields, 0, 1 << 53, path + "/research_points")
	_range(p.research_percent, 0, 100, path + "/research_percent")
	_range(p.research_field, 0, _tech_fields - 1, path + "/research_field")
	_range(p.next_research_field, 0, Player.NEXT_FIELD_LOWEST, path + "/next_research_field")
	if p.relations.size() != _state.players.size():
		_err(path + "/relations", "must have one entry per player")
	for i in p.relations.size():
		if not Player.RELATIONS.has(p.relations[i]):
			_err("%s/relations/%d" % [path, i], "must be one of " + ", ".join(Player.RELATIONS))
	for i in p.ship_designs.size():
		_check_design(p.ship_designs[i], false, "%s/ship_designs/%d" % [path, i])
	for i in p.starbase_designs.size():
		_check_design(p.starbase_designs[i], true, "%s/starbase_designs/%d" % [path, i])
	for i in p.trader_parts.size():
		_content_ref(p.trader_parts[i], "part", "%s/trader_parts/%d" % [path, i])


func _check_race(r: Race, path: String) -> void:
	if _content_ref(r.primary_trait, "trait", path + "/primary_trait"):
		if _content.trait_def(r.primary_trait).get("kind") != "primary":
			_err(path + "/primary_trait", "is not a primary trait")
	var previous := ""
	for i in r.lesser_traits.size():
		var id := r.lesser_traits[i]
		var at := "%s/lesser_traits/%d" % [path, i]
		if id <= previous:
			_err(at, "lesser traits must be sorted and unique")
		previous = id
		if _content_ref(id, "trait", at) and _content.trait_def(id).get("kind") != "lesser":
			_err(at, "is not a lesser trait")
	for axis in 3:
		_check_hab_axis(r, axis, "%s/hab/%d" % [path, axis])
	_range(r.growth_rate, 1, 100, path + "/growth_rate")
	for field in [
		"resources_per_colonist",
		"factory_output",
		"factory_cost",
		"factories_operated",
		"mine_output",
		"mine_cost",
		"mines_operated",
	]:
		_range(r.get(field), 1, 100, "%s/%s" % [path, field])
	_list_range(r.research_costs, _tech_fields, 0, 2, path + "/research_costs")
	_range(r.logo, -1, 31, path + "/logo")


func _check_hab_axis(r: Race, axis: int, path: String) -> void:
	var low: int = r.hab_low[axis] if axis < r.hab_low.size() else -2
	var center: int = r.hab_center[axis] if axis < r.hab_center.size() else -2
	var high: int = r.hab_high[axis] if axis < r.hab_high.size() else -2
	if low == -1 and center == -1 and high == -1:
		return
	if low < 0 or high > 100 or not (low <= center and center <= high):
		_err(path, "needs 0 <= low <= center <= high <= 100, or -1 in all three (immune)")


func _check_design(d: Design, starbase: bool, path: String) -> void:
	var limit := _limit("starbase_designs" if starbase else "ship_designs")
	_range(d.slot, 0, limit - 1, path + "/slot")
	if not _content_ref(d.hull, "hull", path + "/hull"):
		return
	var hull := _content.hull(d.hull)
	if PartRules.design_picture(d.picture, hull) != d.picture:
		_err(path + "/picture", "must be one of the hull's four pictures")
	if bool(hull.get("starbase", false)) != starbase:
		_err(path + "/hull", "is a starbase hull" if not starbase else "is not a starbase hull")
	var slots: Array = hull["slots"]
	if d.parts.size() != slots.size():
		_err(path + "/parts", "must have one entry per hull slot (%d)" % slots.size())
		return
	for i in slots.size():
		_check_design_slot(d.parts[i], slots[i], "%s/parts/%d" % [path, i])


func _check_design_slot(entry: DesignSlot, slot: Dictionary, path: String) -> void:
	if entry.part.is_empty():
		if entry.count != 0:
			_err(path + "/count", "must be 0 for an empty slot")
		return
	if not _content_ref(entry.part, "part", path + "/part"):
		return
	if not (slot["accepts"] as Array).has(_content.part(entry.part)["category"]):
		_err(path + "/part", "this slot does not accept that part")
	_range(entry.count, 1, slot["max"], path + "/count")


# --- Planets ---------------------------------------------------------------------------------


func _check_planet(pl: Planet, path: String) -> void:
	_owner(pl.owner, path + "/owner")
	_list_range(pl.environment, 3, 0, 100, path + "/environment")
	_list_range(pl.environment_original, 3, 0, 100, path + "/environment_original")
	_list_range(pl.concentration, 3, 0, 255, path + "/concentration")
	_list_range(pl.concentration_fraction, 3, 0, 255, path + "/concentration_fraction")
	_list_range(pl.surface, 3, 0, 1 << 53, path + "/surface")
	_range(pl.population, 0, 1 << 53, path + "/population")
	_range(pl.extra_colonists, 0, 99, path + "/extra_colonists")
	_range(pl.mines, 0, MAX_INSTALLATIONS, path + "/mines")
	_range(pl.factories, 0, MAX_INSTALLATIONS, path + "/factories")
	_range(pl.defenses, 0, MAX_INSTALLATIONS, path + "/defenses")
	if pl.starbase != null:
		if pl.owner < 0:
			_err(path + "/starbase", "an unowned planet has no starbase")
		elif _state.player(pl.owner) != null:
			if _state.player(pl.owner).starbase_design(pl.starbase.design) == null:
				_err(path + "/starbase/design", "the owner has no starbase design in that slot")
		_range(pl.starbase.damage, 0, MAX_STARBASE_DAMAGE, path + "/starbase/damage")
	if pl.mass_driver_target != -1:
		_planet_ref(pl.mass_driver_target, path + "/mass_driver_target")
	_range(pl.mass_driver_warp, 0, MAX_DRIVER_WARP, path + "/mass_driver_warp")
	if pl.route != -1:
		_planet_ref(pl.route, path + "/route")


# --- Fleets ----------------------------------------------------------------------------------


func _check_fleet(f: Fleet, path: String) -> void:
	if _owner(f.owner, path + "/owner") and f.owner < 0:
		_err(path + "/owner", "a fleet must have an owner")
	_range(f.number, 0, _limit("fleets_per_player") - 1, path + "/number")
	if f.planet != -1:
		_planet_ref(f.planet, path + "/planet")
	if f.stacks.is_empty():
		_err(path + "/stacks", "a fleet has at least one ship")
	var owner := _state.player(f.owner)
	for i in f.stacks.size():
		var s := f.stacks[i]
		var at := "%s/stacks/%d" % [path, i]
		if owner != null and owner.ship_design(s.design) == null:
			_err(at + "/design", "the owner has no ship design in that slot")
		_range(s.count, 1, _limit("ships_per_stack"), at + "/count")
		_damage(s.damaged_percent, s.damage, at)
		_list_range(s.paid, 4, 0, 1 << 53, at + "/paid")
	_list_range(f.cargo, 5, 0, 1 << 53, path + "/cargo")
	if f.waypoints.is_empty():
		_err(path + "/waypoints", "a fleet always has its current position as the first waypoint")
	if f.waypoints.size() > _limit("waypoints"):
		_err(path + "/waypoints", "more than %d waypoints" % _limit("waypoints"))
	for i in f.waypoints.size():
		_check_waypoint(f.waypoints[i], "%s/waypoints/%d" % [path, i])


func _check_waypoint(wp: Waypoint, path: String) -> void:
	_range(wp.warp, 0, MAX_WARP, path + "/warp")
	var found := true
	match wp.target:
		"planet":
			found = _state.planet(wp.target_id) != null
		"fleet":
			found = _state.fleet(wp.target_owner, wp.target_id) != null
		"minefield", "packet", "wormhole", "trader":
			found = _find_object(wp.target + "s", wp.target_owner, wp.target_id) != null
	if not found:
		_err(path + "/target", "no such %s" % wp.target)


# --- Space objects ---------------------------------------------------------------------------


func _check_space_objects() -> void:
	if _state.space_object_count() > _limit("space_objects"):
		_err("/", "more than %d space objects" % _limit("space_objects"))
	var numbers := _limit("space_object_numbers")
	for i in _state.minefields.size():
		var m := _state.minefields[i]
		var path := "/minefields/%d" % i
		_numbered(m.owner, m.number, numbers, path)
		_range(m.mines, 0, 1 << 53, path + "/mines")
		_players(m.seen_by, path + "/seen_by")
	for i in _state.packets.size():
		var pk := _state.packets[i]
		var path := "/packets/%d" % i
		_numbered(pk.owner, pk.number, numbers, path)
		_list_range(pk.minerals, 3, 0, 1 << 53, path + "/minerals")
		if pk.salvage and (pk.destination != -1 or pk.warp != 0):
			_err(path, "salvage has no destination and warp 0")
		if not pk.salvage:
			_planet_ref(pk.destination, path + "/destination")
			_range(pk.warp, 1, MAX_WARP, path + "/warp")
	for i in _state.wormholes.size():
		var w := _state.wormholes[i]
		var path := "/wormholes/%d" % i
		_range(w.number, 0, numbers - 1, path + "/number")
		if w.other_end != -1 and _find_object("wormholes", -1, w.other_end) == null:
			_err(path + "/other_end", "no such wormhole")
		_players(w.seen_by, path + "/seen_by")
	for i in _state.traders.size():
		var t := _state.traders[i]
		_range(t.number, 0, numbers - 1, "/traders/%d/number" % i)
		_players(t.met, "/traders/%d/met" % i)
		if not t.item.is_empty():
			_content_ref(t.item, "part", "/traders/%d/item" % i)


func _find_object(list_name: String, owner: int, number: int) -> ModelObject:
	for obj: ModelObject in _state.get(list_name):
		var obj_owner: Variant = obj.get("owner")
		if (-1 if obj_owner == null else obj_owner) == owner and obj.get("number") == number:
			return obj
	return null


func _numbered(owner: int, number: int, limit: int, path: String) -> void:
	if _owner(owner, path + "/owner") and owner < 0:
		_err(path + "/owner", "must have an owner")
	_range(number, 0, limit - 1, path + "/number")


# --- Helpers ---------------------------------------------------------------------------------


func _limit(name: String) -> int:
	return _content.constant("constant.limits." + name)


func _err(path: String, message: String) -> void:
	_errors.append("%s: %s" % [path, message])


func _range(value: int, low: int, high: int, path: String) -> bool:
	if value < low or value > high:
		_err(path, "must be %d .. %d, not %d" % [low, high, value])
		return false
	return true


func _list_range(values: Array[int], size: int, low: int, high: int, path: String) -> void:
	if values.size() != size:
		_err(path, "must have %d entries" % size)
		return
	for i in size:
		_range(values[i], low, high, "%s/%d" % [path, i])


## A player index or -1. True when valid.
func _owner(owner: int, path: String) -> bool:
	return _range(owner, -1, _state.players.size() - 1, path)


func _players(indices: Array[int], path: String) -> void:
	for i in indices.size():
		_range(indices[i], 0, _state.players.size() - 1, "%s/%d" % [path, i])
		if i > 0 and indices[i] <= indices[i - 1]:
			_err("%s/%d" % [path, i], "must be sorted and unique")


func _planet_ref(id: int, path: String) -> void:
	if _state.planet(id) == null:
		_err(path, "no planet %d" % id)


func _content_ref(id: String, type_name: String, path: String) -> bool:
	if not _content.has_def(id) or _content.type_of(id) != type_name:
		_err(path, "no %s '%s' in the loaded content" % [type_name, id])
		return false
	return true


func _damage(percent: int, damage: int, path: String) -> void:
	_range(percent, 0, 100, path + "/damaged_percent")
	_range(damage, 0, MAX_STACK_DAMAGE, path + "/damage")
