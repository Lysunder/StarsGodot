class_name ProductionList
extends RefCounted
## What a planet can be given to build (S09 section 9, `BuildProductionList@10c8:0100`): ship
## designs its starbase's dock takes, other starbase designs, then the standard items that make
## sense there, in the original's order.

## Standard items by effect, in the order the list shows them (S09 section 9, steps 3 to 8).
const EFFECT_ORDER: Array[String] = [
	"genesis", "packet", "factories", "mines", "defenses", "alchemy", "scanner", "terraform"
]


## The planet's list: {item, design, starbase} (item "" for a design). `can_terraform`: terraforming
## can still change the planet (S10).
static func entries(
	planet: Planet, owner: Player, content: ContentRegistry, can_terraform: bool
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base: Design = null
	if planet.starbase != null:
		base = owner.starbase_design(planet.starbase.design)
	var dock := int(content.hull(base.hull).get("dock", 0)) if base != null else 0
	if dock != 0:
		for d in owner.ship_designs:
			if dock < 0 or PartRules.mass(d, content) <= dock:
				out.append({"item": "", "design": d.slot, "starbase": false})
	for d in owner.starbase_designs:
		if base == null or d.slot != planet.starbase.design:
			out.append({"item": "", "design": d.slot, "starbase": true})
	var standard := []
	var autos := []
	var others := []
	var order := PartRules.tech_order(content)
	for item_id in content.ids("production_item"):
		var def := content.get_def("production_item", item_id)
		var effect := str(def.get("effect", ""))
		var at := int(def.get("order", 0))
		if def.get("auto", false):
			var skip := "colony.skips_auto_%s" % effect
			if not RaceMath.trait_param(owner.race, content, skip, 0):
				autos.append([at, item_id])
		elif not EFFECT_ORDER.has(effect):
			others.append([at, item_id])
		elif _offered(def, effect, planet, owner, content, base, can_terraform, order):
			standard.append([EFFECT_ORDER.find(effect), at, item_id])
	standard.sort()
	autos.sort()
	others.sort()
	for s: Array in standard:
		out.append({"item": s[2], "design": -1, "starbase": false})
	for list: Array in [others, autos]:
		for s: Array in list:
			out.append({"item": s[1], "design": -1, "starbase": false})
	return out


## How many more units of item `item_id` the planet has room for with `queued` already in its
## queue (S09 section 9, issue #16): factories, mines and defenses up to the planet's maximum (S08)
## less those built; -1 for an item without a limit (auto items only ever build what fits).
static func room(
	planet: Planet, owner: Player, content: ContentRegistry, item_id: String, queued: int
) -> int:
	var def := content.get_def("production_item", item_id)
	if def.get("auto", false):
		return -1
	var race := owner.race
	var left := -1
	match str(def.get("effect", "")):
		"factories":
			left = PlanetEconomy.max_factories(planet, race, content) - planet.factories
		"mines":
			left = PlanetEconomy.max_mines(planet, race, content) - planet.mines
		"defenses":
			left = PlanetEconomy.max_defenses(planet, race, content) - planet.defenses
		_:
			return -1
	return maxi(left - queued, 0)


## Whether a standard (not auto) item belongs in the planet's list (S09 section 9).
static func _offered(
	def: Dictionary,
	effect: String,
	planet: Planet,
	owner: Player,
	content: ContentRegistry,
	base: Design,
	can_terraform: bool,
	order: Dictionary
) -> bool:
	var race := owner.race
	match effect:
		"genesis":
			var part := str(def.get("part", ""))
			return content.has_def(part) and PartRules.available(content.part(part), owner, order)
		"packet":
			return base != null and PartRules.driver_warp(base, content) > 0
		"factories":
			return planet.factories < PlanetEconomy.max_factories(planet, race, content)
		"mines":
			return planet.mines < PlanetEconomy.max_mines(planet, race, content)
		"defenses":
			return planet.defenses < PlanetEconomy.max_defenses(planet, race, content)
		"scanner":
			# only the "best scanner" item, on a planet without one (the scanner improves itself)
			return (
				def.get("best", false)
				and not planet.has_scanner
				and not RaceMath.trait_param(race, content, "production.no_planetary_scanner", 0)
			)
		"terraform":
			return can_terraform
	return true
