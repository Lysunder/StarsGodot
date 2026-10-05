class_name DesignView
extends RefCounted
## What the ship designer (M11 step 5) asks of a player's view: their designs, the hulls and
## parts they can use, and a design's totals. Reads the same state as its PlayerView.

var _state: GameState
var _content: ContentRegistry
var _player: int = 0


func _init(state: GameState, content: ContentRegistry, player: int) -> void:
	_state = state
	_content = content
	_player = player


func _me() -> Player:
	return _state.player(_player)


## The player's ship or starbase designs, by slot.
func designs(starbase: bool) -> Array[Design]:
	return _me().starbase_designs if starbase else _me().ship_designs


## The first empty design slot, or -1 when every slot is taken.
func free_design_slot(starbase: bool) -> int:
	var limit := _content.constant(
		"constant.limits.%s" % ("starbase_designs" if starbase else "ship_designs")
	)
	for slot in limit:
		var d := _me().starbase_design(slot) if starbase else _me().ship_design(slot)
		if d == null:
			return slot
	return -1


## The hulls the player can design with now (S04), by name.
func available_hulls(starbase: bool) -> Array[String]:
	var order := PartRules.tech_order(_content)
	var out: Array[String] = []
	for id in _content.ids("hull"):
		var hull := _content.hull(id)
		if (
			bool(hull.get("starbase", false)) == starbase
			and PartRules.available(hull, _me(), order)
		):
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool: return _by_tech(a) < _by_tech(b))
	return out


## The parts of the given categories the player can use now, least tech first.
func available_parts(categories: Array) -> Array[String]:
	var order := PartRules.tech_order(_content)
	var out: Array[String] = []
	for id in _content.ids("part"):
		var part := _content.part(id)
		if categories.has(part["category"]) and PartRules.available(part, _me(), order):
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool: return _by_tech(a) < _by_tech(b))
	return out


## Sort key for hulls and parts: total tech required, then name.
func _by_tech(id: String) -> String:
	var tech: Dictionary = _content.get_def(_content.type_of(id), id).get("tech", {})
	var total := 0
	for field: String in tech:
		total += int(tech[field])
	return "%03d %s" % [total, _content.display_name(id)]


## A new design on the hull with every slot empty.
func blank_design(hull: String) -> Design:
	var d := Design.new()
	d.hull = hull
	d.picture = int(_content.hull(hull).get("pictures", 0))
	for _slot: Variant in _content.hull(hull)["slots"]:
		d.parts.append(DesignSlot.new())
	return d


## What the designer shows for a design: cost [ironium, boranium, germanium, resources], mass,
## armor (S04), the shield parts' total (before battle adjustments, M9), fuel and cargo capacity,
## the range at each warp 1..10 (0: can't move) and why the design can't be saved ("" if it can).
func design_stats(design: Design, starbase: bool) -> Dictionary:
	var shields := 0
	for slot in design.parts:
		if not slot.part.is_empty():
			shields += slot.count * int(_content.part(slot.part).get("stats", {}).get("shield", 0))
	var ranges: Array[int] = []
	if not starbase:
		for warp in range(1, 11):
			ranges.append(Movement.design_range(design, _me(), warp, _content))
	var problem := PartRules.design_problem(design, starbase, _me(), _content)
	if problem.is_empty() and design.name.strip_edges().is_empty():
		problem = "the design needs a name"
	return {
		"cost": ProductionCosts.design_cost(design, _me(), _content),
		"mass": PartRules.mass(design, _content),
		"armor": PartRules.armor(design, _content, _me().race),
		"shields": shields,
		"fuel": PartRules.fuel_capacity(design, _content),
		"cargo": PartRules.cargo_capacity(design, _content),
		"ranges": ranges,
		"problem": problem,
	}
